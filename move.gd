extends Spatial

var speed := 10
var gravity := 9.8
var jump := 1
var mouse_sensitivity := 0.05
var acceleration := 5
var rough_friction := 4
var no_friction := 0
var is_grounded :bool = false

var direction := Vector3()
var mouse_captured: bool

onready var head = $Head
onready var rot = $Head/Rot

var player_physics_material = load("res://Physics/player.tres")

# Player Look
func _input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		rot.rotate_x(deg2rad(-event.relative.y * mouse_sensitivity))
		rot.rotation.x = clamp(rot.rotation.x, deg2rad(-90), deg2rad(90))

# Capture mouse on load
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)	
	mouse_captured = true
func _process(_delta):
	# Capture/release mouse on 'Esc' press
	if Input.is_action_just_pressed("ui_cancel"):
		if (mouse_captured == true):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mouse_captured = false
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			mouse_captured = false
	
	# Any input pressed -> remove rigidbody friction to prevent sticking (mimics move and slide)
	if (is_any_movement_just_pressed()):
		player_physics_material.rough = false
		player_physics_material.friction = no_friction
	# All input released -> change rigidbody physics material to high friction
	elif (is_all_movement_just_released()):
		player_physics_material.rough = true
		player_physics_material.friction = rough_friction
	
# Return true if any of the movement keys were just pressed
func is_any_movement_just_pressed():
	return (Input.is_action_just_pressed("move_forward") or
	 Input.is_action_just_pressed("move_backward") or
	 Input.is_action_just_pressed("move_left") or
	 Input.is_action_just_pressed("move_right"))

# Returns true if all movement keys are released after at least one was pressed
func is_all_movement_just_released():
	if (Input.is_action_just_released("move_forward") or
	 Input.is_action_just_released("move_backward") or
	 Input.is_action_just_released("move_left") or
	 Input.is_action_just_released("move_right")):
		return (!Input.is_action_pressed("move_forward") and
		 !Input.is_action_pressed("move_backward") and
		 !Input.is_action_pressed("move_right") and
		 !Input.is_action_pressed("move_left"))

#DevNotes:
	# If jumped and lets go of space, apply slight downward force.
	# If forced above max velocity(by impulse or collision), don't do velocity limiting during input except
	 #in the axes on which the velocity is over the max speed.
	# FSM for Rigidbody controller?:
		# Air(If not grounded) - (add small force in direction held)
		# Idle(no input) - (Act against any current vel), or run timer and dec vel with it until stopped
		# Accel(input) - (Force towards direction)
		# AtSpeed(grounded, witht input, at speed limit) - (SetVelocity state if over velocity limit and direction held)
	# remove friction in the air as well. On becoming grounded, scale it up over a fraction of a second to allow a small slide.
	 # I don't think I can work around that with the given physics.
	# Looks like while fixing the last bug that caused edge case drifting, I caused acceleration bugs.
	 # I suppose the next plan is to make the force grow over a time which is based on the degree of vector change.

func _integrate_forces(state):
	# Handle jump
	is_grounded = false
	# If the player body is contacting something
	if (state.get_contact_count() > 0):
		# Get the normal of the point of contact
		var contact_normal = state.get_contact_local_normal(0)
		# If the contact normal is facing up, the player is grounded
		if (contact_normal.y > 0):
			is_grounded = true
	# If the player tried to jump, and is grounded, apply a force vector times the jump multiplier
	if (Input.is_action_just_pressed("jump")):
		if(is_grounded):
			state.apply_central_impulse(Vector3(0,1,0) * jump)

	# Initialize the movement vector and get the current velocity of the player
	var move = Vector3()
	var current = state.get_linear_velocity()

## if not grounded, use air-controls
	# Handle diagonal inputs
	if (Input.is_action_pressed("move_forward") and Input.is_action_pressed("move_right")): 
		# Add the closest 2 cardinal x/z vectors and normalize the result
		move = (-head.transform.basis.z + head.transform.basis.x).normalized()
	elif (Input.is_action_pressed("move_backward") and Input.is_action_pressed("move_right")): 
		move = (head.transform.basis.z + head.transform.basis.x).normalized()
	elif (Input.is_action_pressed("move_backward") and Input.is_action_pressed("move_left")): 
		move = (head.transform.basis.z + -head.transform.basis.x).normalized()
	elif (Input.is_action_pressed("move_forward") and Input.is_action_pressed("move_left")): 
		move = (-head.transform.basis.z + -head.transform.basis.x).normalized()
		
	# Handle z-axis inputs
	elif Input.is_action_pressed("move_forward"):
		# Normalized movement vector based on forward look direction (-z), multiplied by speed
		move = -head.transform.basis.z
	elif Input.is_action_pressed("move_backward"):
		move = head.transform.basis.z
		
	# Handle x-axis inputs
	elif Input.is_action_pressed("move_right"):
		# Normalized movement vector based on sideways direction (x), multiplied by speed
		move = head.transform.basis.x
	elif Input.is_action_pressed("move_left"):
		move = -head.transform.basis.x

	move *= speed # Multiply the normalized move vector by speed
	current = state.get_linear_velocity()
	var limit = current # The current velocity to be limited

	### set x and z axes speed limit for normalized movement based on move direction ###
	#	X-AXIS
	# If the move vector is in the direction for the respective axis the player is moving,
	# and the current velocity is greater than the normalized limit for that direction,
	if ((move.x > 0 and current.x > move.x) or
	 (move.x < 0 and current.x < move.x) or
	 # or if the current velocity is in the opposite direction of the move vector for this axis,
	 (current.x < 0 and move.x > 0) or
	 (current.x > 0 and move.x < 0)):
	 # set the velocity limit according to the move direction
		limit.x = move.x
	#   Z-AXIS 
	if ((move.z > 0 and current.z > move.z) or 
	 (move.z < 0 and current.z < move.z) or
	 (current.z < 0 and move.z > 0) or
	 (current.z > 0 and move.z < 0)):
		limit.z = move.z
	
	# If velocity on an axis was over the limit, velocity on that axis will be set to the normalized limit
	state.set_linear_velocity(limit)
	# Add the intended force
	state.add_central_force(move * acceleration)
