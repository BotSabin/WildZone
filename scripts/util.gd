extends RefCounted
## Small helpers for building 3D shapes from primitives (no external models).

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


static func mat(c: Color, rough: float = 0.85, glow: float = 0.0, metal: float = 0.0) -> StandardMaterial3D:
	var key: String = "%s|%.2f|%.2f|%.2f" % [c.to_html(), rough, glow, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if c.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


static func metal(c: Color) -> StandardMaterial3D:
	return mat(c, 0.35, 0.0, 0.75)


static func _add(parent: Node, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, pos: Vector3, c: Color, glow: float = 0.0) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(parent, bm, pos, mat(c, 0.85, glow))


static func box_m(parent: Node, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(parent, bm, pos, m)


## Unit sphere scaled to an ellipsoid with the given radii.
static func ellipsoid(parent: Node, radii: Vector3, pos: Vector3, c: Color, glow: float = 0.0) -> MeshInstance3D:
	if not _meshes.has("sphere"):
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 18
		sm.rings = 10
		_meshes["sphere"] = sm
	var mi := _add(parent, _meshes["sphere"], pos, mat(c, 0.85, glow))
	mi.scale = radii
	return mi


static func sphere(parent: Node, radius: float, pos: Vector3, c: Color, glow: float = 0.0) -> MeshInstance3D:
	return ellipsoid(parent, Vector3(radius, radius, radius), pos, c, glow)


static func capsule(parent: Node, radius: float, height: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(height, radius * 2.0)
	cm.radial_segments = 12
	cm.rings = 4
	return _add(parent, cm, pos, mat(c))


static func cyl(parent: Node, top: float, bottom: float, height: float, pos: Vector3, c: Color, sides: int = 12, glow: float = 0.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	return _add(parent, cm, pos, mat(c, 0.85, glow))


static func cyl_m(parent: Node, top: float, bottom: float, height: float, pos: Vector3, m: Material, sides: int = 12) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	return _add(parent, cm, pos, m)


static func pivot(parent: Node, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


static func label(parent: Node, text: String, pos: Vector3, size: int = 48, c: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = c
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l


## Hide small details far away (saves a lot of draw calls).
static func set_view_range(node: Node, range_end: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = range_end
	for c in node.get_children():
		set_view_range(c, range_end)


static func set_shadows(node: Node, on: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		set_shadows(c, on)


## Replaces every material under node with one material (used for build previews).
static func override_all(node: Node, m: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = m
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		override_all(c, m)


# ==================================================
# MESH BAKING (performance)
# ==================================================
## Merges plain-coloured sibling meshes into one mesh with vertex colours.
## Hundreds of tiny boxes/spheres become one draw call, which keeps the game
## smooth in browsers and on weak laptops. Recurses into child Node3Ds, but
## only ever merges meshes that share the same parent, so animated pivots
## (legs, arms, heads) keep moving independently.
static var _vc_mat: StandardMaterial3D


static func vertex_color_material() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.vertex_color_is_srgb = true
		_vc_mat.roughness = 0.85
	return _vc_mat


static func _bakeable(c: Node) -> bool:
	if not (c is MeshInstance3D) or c.get_child_count() > 0:
		return false
	var mi := c as MeshInstance3D
	if not mi.visible or mi.mesh == null:
		return false
	var m := mi.material_override as StandardMaterial3D
	if m == null or m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return false
	return m.albedo_texture == null


static func bake(parent: Node) -> void:
	for c in parent.get_children():
		if c is Node3D and not (c is MeshInstance3D):
			bake(c)
	var list: Array = []
	for c in parent.get_children():
		if _bakeable(c):
			list.append(c)
	if list.size() < 2:
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for c in list:
		var mi := c as MeshInstance3D
		var col: Color = (mi.material_override as StandardMaterial3D).albedo_color
		var xf: Transform3D = mi.transform
		var nb: Basis = xf.basis.inverse().transposed()
		for s in range(mi.mesh.get_surface_count()):
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var base: int = verts.size()
			for i in range(v.size()):
				verts.append(xf * v[i])
				norms.append((nb * n[i]).normalized() if i < n.size() else Vector3.UP)
				cols.append(col)
			if ind.is_empty():
				for i in range(v.size()):
					idx.append(base + i)
			else:
				for j in ind:
					idx.append(base + j)
		parent.remove_child(mi)
		mi.queue_free()
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var out := MeshInstance3D.new()
	out.name = "Baked"
	out.mesh = am
	out.material_override = vertex_color_material()
	parent.add_child(out)
