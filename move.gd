extends Spatial

var speed = 15
var gravity = 9.8
var jump = 9
var mouse_sensitivity = 0.05

var direction = Vector3()
var mouse_captured

onready var head = $Head
onready var rot = $Head/Rot

### Player Look
func _input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		rot.rotate_x(deg2rad(-event.relative.y * mouse_sensitivity))
		rot.rotation.x = clamp(rot.rotation.x, deg2rad(-90), deg2rad(90))

### Mouse capture/free
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)	
	mouse_captured = 1
func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		if (mouse_captured == 1):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mouse_captured = 0
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			mouse_captured = 1

# FSM for Rigidbody controller?
	# Air(If not grounded) - (add small force in direction held if cannot subtract velocity directly)
	# Idle(no input) - (Act against any current vel), or run timer and dec vel with it until stopped
	# Accel(input) - (Force towards direction),
	# AtSpeed(grounded, witht input, at speed limit) - (SetVelocity state if over velocity limit and direction held)

var once = false
func _integrate_forces(state):	
	# Before continuing, check an is_grounded raycast
		# if not grounded, use air-controls
		# prevent popping up when moving on slopes and jumping up to edges because of capsule collider
		# prevent sliding when becoming grounded
	
	# Consider using friction and creating a move_and_slide function for the
	# Change body material when not input to be one with high friction
	
	# Handle jump
	if (Input.is_action_just_pressed("jump")):
		state.apply_central_impulse(Vector3(0,1,0)*jump)
	
	var move = Vector3()
	var current = state.get_linear_velocity()
	
	if (once == false):
		once = true
		direction = -head.transform.basis.z
		state.apply_central_impulse(direction*20)
	
	## Velocity limits need to be removed for impulses & collisions during input
	# Handle diagonal movements # Stop will be handled by single key press logic
	if (Input.is_action_pressed("move_forward") and Input.is_action_pressed("move_right")): 
		move = (-head.transform.basis.z + head.transform.basis.x).normalized() * speed
		move.y = current.y
		state.set_linear_velocity(move)
	elif (Input.is_action_pressed("move_backward") and Input.is_action_pressed("move_right")): 
		move = (head.transform.basis.z + head.transform.basis.x).normalized() * speed
		move.y = current.y
		state.set_linear_velocity(move)
	elif (Input.is_action_pressed("move_backward") and Input.is_action_pressed("move_left")): 
		move = (head.transform.basis.z + -head.transform.basis.x).normalized() * speed
		move.y = current.y
		state.set_linear_velocity(move)
	elif (Input.is_action_pressed("move_forward") and Input.is_action_pressed("move_left")): 
		move = (-head.transform.basis.z + -head.transform.basis.x).normalized() * speed
		move.y = current.y
		state.set_linear_velocity(move)

	# Handle z-axis movement
	elif Input.is_action_pressed("move_forward"):
		# Normalized movement vector based on forward look direction (-z), multiplied by speed
		move = -head.transform.basis.z * speed

		current = state.get_linear_velocity()
		var limit = current # The current velocity to be limited
		# set x-axis speed limit for normalized movement based on look direction
		if (move.x > 0 and current.x > move.x) || (move.x < 0 and current.x < move.x):
			limit.x = move.x
		# set z-axis speed limit for normalized movement based on look direction
		if (move.z > 0 and current.z > move.z) || (move.z < 0 and current.z < move.z):
			limit.z = move.z
		# If an axis was over the limit, it will be set to the limit in the limit variable
		state.set_linear_velocity(limit)
		# Add the intended force
		state.add_central_force(move)

### Refactor 
	elif (Input.is_action_just_released("move_forward")):
		move = Vector3()
		move.y = current.y
		state.set_linear_velocity(move)
	elif Input.is_action_pressed("move_backward"):
		move = head.transform.basis.z * speed
		
		move.y = current.y
		state.set_linear_velocity(move)
		print(state.get_linear_velocity())
	elif Input.is_action_just_released("move_backward"):
		move.y = current.y
		state.set_linear_velocity(move)

	# Handle x-axis movement
	elif Input.is_action_pressed("move_right"):
		move = head.transform.basis.x *  speed
		move.y = current.y
		state.set_linear_velocity(move)
	elif Input.is_action_just_released("move_right"):
		move.y = current.y
		state.set_linear_velocity(move)
	elif Input.is_action_pressed("move_left"):
		move = -head.transform.basis.x * speed
		move.y = current.y
		state.set_linear_velocity(move)
	elif Input.is_action_just_released("move_left"):
		move.y = current.y
		state.set_linear_velocity(move)
