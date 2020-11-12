extends RigidBody

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

var once = false
func _integrate_forces(state):	
	if (once == false):
		once = true
		var direction = Vector3(0,0,1)
		#if state.get_linear_velocity().z < 5:
		state.apply_central_impulse(direction*250)
