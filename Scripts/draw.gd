tool
extends Spatial

# Test tool to draw lines
# Note: Drawing at translation draws at top of capsule, not player origin

var raycast_list = Array()
var start = 1.23
var bottom = 0.26
# Cardinal vector distance
var cv_dist = 0.45
# Secondary vector distance
# Added to 2 cardinal vectors to result in a diagonal with the same maginitude of a cardinal vector
var sv_dist= cv_dist/sqrt(2)

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func _process(_delta):
	raycast_list.clear()
	
	for i in 8:
		var loc = get_node('Player').translation
		loc.y -= start
		match i:
			# Cardinal vectors
			0: 
				loc.z -= cv_dist
			1:
				loc.z += cv_dist
			2:
				loc.x += cv_dist
			3:
				loc.x -= cv_dist
			# Secondary vectors
			4:
				loc.z -= sv_dist
				loc.x += sv_dist
			5:
				loc.z += sv_dist
				loc.x += sv_dist	
			6:
				loc.z -= sv_dist
				loc.x -= sv_dist
			7:
				loc.z += sv_dist
				loc.x -= sv_dist
		var loc2 = loc
		loc2.y -= bottom
		raycast_list.append([loc,loc2])
	var draw = get_node("draw")
	draw.clear()
	for array in raycast_list:
		draw.begin(Mesh.PRIMITIVE_LINE_STRIP)
		draw.add_vertex(array[0])
		draw.add_vertex(array[1])
		draw.end()
