extends Spatial

var speed = 15
var gravity = 9.8
var jump = 9
var mouse_sensitivity = 0.05

var direction = Vector3()

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
func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# FSM for Rigidbody controller?
	# Air(If not grounded) - (add small force in direction held if cannot subtract velocity directly)
	# Idle(no input) - (Act against any current vel), or run timer and dec vel with it until stopped
	# Accel(input) - (Force towards direction),
	# AtSpeed(grounded, witht input, at speed limit) - (SetVelocity state if over velocity limit and direction held)

func _integrate_forces(state):	
	# Before continuing, check an is_grounded raycast
		# if not grounded, use air-controls
		# prevent popping up when moving on slopes and jumping up to edges because of capsule collider
		# prevent sliding when becoming grounded
	
	# Consider using friction and creating a move_and_slide function for the
	# rigidbody controller using the collision normals and current move vector
	
	# Add timer for smooth movments on input?
	
	# Handle jump	
	if (Input.is_action_just_pressed("jump")):
		state.apply_central_impulse(Vector3(0,1,0)*jump)
	
	var move = Vector3()
	var current = state.get_linear_velocity()
	
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
		move = -head.transform.basis.z * speed
		move.y = current.y
		state.set_linear_velocity(move)
	elif (Input.is_action_just_released("move_forward")):
		move.y = current.y
		state.set_linear_velocity(move)
	elif Input.is_action_pressed("move_backward"):
		move = head.transform.basis.z * speed
		move.y = current.y
		state.set_linear_velocity(move)
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
