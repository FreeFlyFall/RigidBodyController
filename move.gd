extends Spatial

var speed := 100
export var jump: float = 10
export var mouse_sensitivity: = 0.05
#export var friction: = 50
var is_grounded: bool = false
var speed_limit = 10
var friction = 5

var direction: = Vector3()
var mouse_captured: bool

onready var head = $Head
onready var yaw = $Head/Yaw

var player_physics_material = load("res://Physics/player.tres")

# Player Look
func _input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		yaw.rotate_x(deg2rad(-event.relative.y * mouse_sensitivity))
		yaw.rotation.x = clamp(yaw.rotation.x, deg2rad(-90), deg2rad(90))

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
			mouse_captured = true
	
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
	# Change movement vector to be perpendicular to the contact slope
	# Change linear damp while in air
	# If forced above max velocity(by impulse or collision), don't do velocity limiting during input
	 # ignore input in on the axes on which the velocity is over the speed limit
	# FSM for Rigidbody controller?:
		# Air(If not grounded) - (add small force in direction held)
		# Idle(no input) - (Act against any current vel), or run timer and dec vel with it until stopped
		# Accel(input) - (Force towards direction)
		# AtSpeed(grounded, witht input, at speed limit) - (SetVelocity state if over velocity limit and direction held)
	# remove friction in the air as well. On becoming grounded, scale it up over a fraction of a second to allow a small slide.

func _integrate_forces(state):
	# Set is_grounded
	is_grounded = false
	# If the player body is contacting something
	if (state.get_contact_count() > 0):
		# Get the normal of the point of contact
		var contact_normal = state.get_contact_local_normal(0)
		# If the contact normal is facing up, the player is grounded
		if (contact_normal.y > 0.01):
			is_grounded = true
			player_physics_material.rough = true
			player_physics_material.friction = 5 #friction
			#self.linear_damp = 5
		else:
			player_physics_material.rough = false
			player_physics_material.friction = 0
	# If the player tried to jump, and is grounded, apply a force vector times the jump multiplier
	if (Input.is_action_just_pressed("jump")):
		if(is_grounded):
			state.apply_central_impulse(Vector3(0,1,0) * jump)
			#self.linear_damp = -1
	if (not is_grounded) and Input.is_action_just_released("jump"):
		var jump_fraction = jump / 5
		state.apply_central_impulse(Vector3(0,-1,0) * jump_fraction)

	# Initialize the movement vector and get the current velocity of the player
	var move = Vector3()
	
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
		# Normalized movement vector based on forward look direction (-z)
		move = -head.transform.basis.z
	elif Input.is_action_pressed("move_backward"):
		move = head.transform.basis.z
	# Handle x-axis inputs
	elif Input.is_action_pressed("move_right"):
		# Normalized movement vector based on sideways direction (x)
		move = head.transform.basis.x
	elif Input.is_action_pressed("move_left"):
		move = -head.transform.basis.x

	if (is_grounded):
		#self.linear_damp = -1 # Use default linear damp
		# If the player is grounded and moving, limit the velocity to the speed limit
		move *= speed
		var vel = state.get_linear_velocity()
		var nvel = vel.normalized() # The normalized player velocity
		# If the players velocity doesn't exceed the normalized movement vector at the speed limit,
		# add the force towards the movement vector
		if ((nvel.x > 0 and vel.x < nvel.x*speed_limit) or (nvel.x < 0 and vel.x > nvel.x*speed_limit)
		or (nvel.z > 0 and vel.z < nvel.z*speed_limit) or (nvel.z < 0 and vel.z > nvel.z*speed_limit)):
			state.add_central_force(move)
	else:
		# Accept input which is sideways and backward from the velocity vector if above the speed limit and reduce the force
		state.add_central_force(move/10)
