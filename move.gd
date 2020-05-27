extends Spatial

# Use the GodotPhysics physics engine

#DevNotes:
	# If forced above max velocity(by impulse or collision), don't do velocity limiting during input
	 # ignore input for the direction in which the velocity is over the speed limit

	# Remove friction in the air as well. On becoming grounded, scale it up over a fraction of a second to allow a small slide

	# If not grounded, use air-controls

	# Add crouch. Crouch during jump while space is held to make landing accurately easier.

	# Fix input to cancel opposing inputs instead of one overriding.

	# Limit jump based on slope normal
	 # upward slope scales to less force
	 # downward slope scales to more force


### Integrate forces vars
export var speed := 100 # 100 # Player speed
export var jump: float # 5 # Jump force multiplier
export var air_control: float # 3 # Air control multiplier
export var mouse_sensitivity: = 0.05
export var speed_limit = 10 # 10 # Default speed limit of the player while grounded
var player_physics_material = load("res://Physics/player.tres")
var friction = player_physics_material.friction # Editor friction value
var is_landing: bool = false # Whether the player has jumped and let go of jump
var slope_normal: Vector3 # Stores normals of contact points for iteration
var upper_slope_normal: Vector3 # Stores the lowest (steepest) slope normal
export var flat_offset = 0.02 # Which normal value offset from 1 by a slope is considered not flat

### Process vars
onready var head = $Head
onready var yaw = $Head/Yaw
onready var camera = $Head/Yaw/Camera
var mouse_captured: bool

### Physics process vars
var is_grounded: bool
var raycast_list = Array()
var start = 1.2 # Start point down from the top of the player to start the raycast
var bottom = 0.29 # Distance down from start to fire the raycast to
# Cardinal vector distance
var cv_dist = 0.45
# Ordinal vector distance
# Added to 2 cardinal vectors to result in a diagonal with the same magnitude of the cardinal vectors
var ov_dist= cv_dist/sqrt(2)


### Player Look
func _input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		yaw.rotate_x(deg2rad(-event.relative.y * mouse_sensitivity))
		yaw.rotation.x = clamp(yaw.rotation.x, deg2rad(-90), deg2rad(90))

func _physics_process(_delta):
	# Get world state for collisions
	var direct_state = get_world().direct_space_state
	raycast_list.clear()
	is_grounded = false
	# Create 9 raycasts around the player capsule
	# They begin towards the edge of the radius and shoot from just
	# below the capsule, to just below the bottom bound of the capsule,
	# with one raycast down from the center
	for i in 9:
		# Get the starting location
		var loc = self.translation
		# subtract a distance to get below the capsule
		loc.y -= start
		# Create the distance from center in a certain direction
		match i:
			# Cardinal vectors
			0: 
				loc.z -= cv_dist # N
			1:
				loc.z += cv_dist # S
			2:
				loc.x += cv_dist # E
			3:
				loc.x -= cv_dist # W
			# Ordinal vectors
			4:
				loc.z -= ov_dist # NE
				loc.x += ov_dist
			5:
				loc.z += ov_dist # SE
				loc.x += ov_dist	
			6:
				loc.z -= ov_dist # NW
				loc.x -= ov_dist
			7:
				loc.z += ov_dist # SW
				loc.x -= ov_dist
		# Copy the current location below the capsule and subtract from it
		var loc2 = loc
		loc2.y -= bottom
		# Add the two vectors for this iteration to the list for the raycast
		raycast_list.append([loc,loc2])
	# Check each raycast for collision
	for array in raycast_list:
		var collision = direct_state.intersect_ray(array[0],array[1],[self])
		if collision:
			is_grounded = true

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

func _integrate_forces(state):
	### Friction and grounding
	# If the player body is contacting something,
	if (state.get_contact_count() > 0):
		var contact_normal_array = []
		# get the normal of the point of contact
		upper_slope_normal = state.get_contact_local_normal(0)
		for i in state.get_contact_count():
			contact_normal_array.insert(i, state.get_contact_local_normal(i))
			# If the contact normal is facing up, the player is grounded
			slope_normal = contact_normal_array[i]
			if (slope_normal < upper_slope_normal): # Lower normal means steeper slope
				upper_slope_normal = slope_normal
		if (upper_slope_normal.y >= 0.5):
			is_grounded = true
	# If the player isn't against a wall or something tilting toward them
	if (is_grounded):
		# If the player meets a transition and the highest slope normal is not flat
		if (state.get_contact_count() in range(2,4) and upper_slope_normal.y < (1 - flat_offset)):
			player_physics_material.rough = false
			player_physics_material.friction = 0
		# Else use normal friction
		else:
			player_physics_material.rough = true
			player_physics_material.friction = friction
	# Else turn it off
	else:
		player_physics_material.rough = false
		player_physics_material.friction = 0

	### Handle jumping
	# If the player tried to jump, and is grounded, apply an upward force times the jump multiplier
	# Apply a downward force once if the player lets go of jump to assist with landing
	if (Input.is_action_just_pressed("jump")):
		if (is_grounded):
			state.apply_central_impulse(Vector3(0,1,0) * jump)
			is_landing = false
			#self.linear_damp = -1
	if (not is_grounded) and Input.is_action_just_released("jump"):
		if (is_landing == false):
			var jump_fraction = jump / 5
			state.apply_central_impulse(Vector3(0,-1,0) * jump_fraction)
			is_landing = true

	### Movement
	# Initialize the movement vector
	var move = Vector3()

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
		# Normalized movement vector based on right direction (x)
		move = head.transform.basis.x
	elif Input.is_action_pressed("move_left"):
		move = -head.transform.basis.x

	var vel = state.get_linear_velocity()
	var nvel = vel.normalized() # The normalized player velocity
	## Ground controls
	if (is_grounded):		
		# If they player is below the speed limit, accept a force in any direction
		if ((nvel.x >= 0 and vel.x < nvel.x*speed_limit) or (nvel.x <= 0 and vel.x > nvel.x*speed_limit) or
		(nvel.z >= 0 and vel.z < nvel.z*speed_limit) or (nvel.z <= 0 and vel.z > nvel.z*speed_limit) or
		(nvel.x == 0 or nvel.z == 0)):
			move = move.cross(slope_normal).cross(slope_normal).cross(slope_normal).cross(slope_normal)
			state.add_central_force(move*speed)
		# If the player's speed is above the limit, and the movement vector
		# faces away from the velocity vector, add the force
		elif (nvel.dot(move) < 0):
			move = move.cross(slope_normal).cross(slope_normal).cross(slope_normal).cross(slope_normal)
			state.add_central_force(move*speed)
		# If the player's speed is above the limit, and the movement vector
		# is facing the velocity, add a force perpendicular to the velocity;
		# the force is to the left if the angle between the the velocity and
		# movement vectors is negative, and to the right if it's positive.
		else:
			var move2 = Vector2(move.x, move.z)
			var nvel2 = Vector2(nvel.x, nvel.z)
			# Get the angle between the velocity and current movement vector
			var angle = nvel2.angle_to(move2)
			# Convert it to degrees
			var theta = rad2deg(angle)

			# If the angle is to the right of the velocity
			if (theta > 0 and theta < 90):
				# Take the cross product between the velocity and the y-axis
				# to get the vector to the right of the velocity
				move = nvel.cross(head.transform.basis.y)
				move = move.cross(slope_normal).cross(slope_normal).cross(slope_normal).cross(slope_normal)
			# If the angle is to the left of the velocity
			elif(theta < 0 and theta > -90):
				# Take the cross product between the y-axis and the velocity
				# to get the vector to the left of the velocity
				move = head.transform.basis.y.cross(nvel)
				move = move.cross(slope_normal).cross(slope_normal).cross(slope_normal).cross(slope_normal)
			state.add_central_force(move*speed)
	## Air controls
	else:
		# If they player is below the speed limit, accept a force in any direction
		if ((nvel.x >= 0 and vel.x < nvel.x*speed_limit) or (nvel.x <= 0 and vel.x > nvel.x*speed_limit) or
		(nvel.z >= 0 and vel.z < nvel.z*speed_limit) or (nvel.z <= 0 and vel.z > nvel.z*speed_limit) or
		(nvel.x == 0 or nvel.z == 0)):
			state.add_central_force(move*air_control)
		# If the player's speed is above the limit, and the movement vector
		# faces away from the velocity vector, add the force
		elif (nvel.dot(move) < 0):
			state.add_central_force(move*air_control)
		# If the player's speed is above the limit, and the movement vector
		# is facing the velocity, add a force perpendicular to the velocity;
		# the force is to the left if the angle between the the velocity and
		# movement vectors is negative, and to the right if it's positive.
		else:
			var move2 = Vector2(move.x, move.z)
			var nvel2 = Vector2(nvel.x, nvel.z)
			# Get the angle between the velocity and current movement vector
			var angle = nvel2.angle_to(move2)
			# Convert it to degrees
			var theta = rad2deg(angle)

			# If the angle is to the right of the velocity
			if (theta > 0 and theta < 90):
				# Take the cross product between the velocity and the y-axis
				# to get the vector to the right of the velocity
				move = nvel.cross(head.transform.basis.y)
			# If the angle is to the left of the velocity
			elif(theta < 0 and theta > -90):
				# Take the cross product between the y-axis and the velocity
				# to get the vector to the left of the velocity
				move = head.transform.basis.y.cross(nvel)
			state.add_central_force(move*air_control)

	# Shotgun jump test
	if (Input.is_action_just_pressed("fire")):
		var direction = Vector3()
		direction = camera.global_transform.basis.z # Opposite of look direction
		state.add_central_force(direction*1500)
