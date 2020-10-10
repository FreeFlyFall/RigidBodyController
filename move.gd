extends Spatial

# Use the GodotPhysics physics engine

#DevNotes to-do:
	# Use raycast towards movement direction to determine which normals to use for movement cross products.
	# Add crouch. Crouch during jump only while space is held to make landing accurately easier.
	# Fix input to cancel opposing inputs instead of one overriding.

### Integrate forces vars
export var accel: int # 100 # Player acceleration force
export var jump: int # 5 # Jump force multiplier
export var air_control: int # 3 # Air control multiplier
export var mouse_sensitivity: = 0.05
export var speed_limit = 10 # 10 # Default speed limit of the player while grounded
var player_physics_material = load("res://Physics/player.tres")
var friction = player_physics_material.friction # Editor friction value
var is_landing: bool = false # Whether the player has jumped and let go of jump
var slope_normal: Vector3 # Stores normals of contact points for iteration
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

# Capture mouse on load
func _ready():
	Input.set_mouse_mode(2) # Captured and hidden

func _input(event):
	# Player look
	if event is InputEventMouseMotion:
		head.rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		yaw.rotate_x(deg2rad(-event.relative.y * mouse_sensitivity))
		yaw.rotation.x = clamp(yaw.rotation.x, deg2rad(-90), deg2rad(90))
	# Capture and release mouse
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == 2:
			Input.set_mouse_mode(0) # Free the mouse
		else:
			Input.set_mouse_mode(2)

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
		# Create the distance from the capsule center in a certain direction
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
		# Add the two points for this iteration to the list for the raycast
		raycast_list.append([loc,loc2])
	# Check each raycast for collision, ignoring the capsule itself
	for array in raycast_list:
		var collision = direct_state.intersect_ray(array[0],array[1],[self])
		if collision:
			is_grounded = true

func _integrate_forces(state):
	var upper_slope_normal: Vector3 # Stores the lowest (steepest) slope normal
	var lower_slope_normal: Vector3 # Stores the highest (flattest) slope normal
	
	### Friction and grounding
	# If the player body is contacting something,
	if (state.get_contact_count() > 0):
		# iterate over the capsule contact points
		for i in state.get_contact_count():
			slope_normal = state.get_contact_local_normal(i)
			if (slope_normal.y < upper_slope_normal.y): # Lower normal means steeper slope
				upper_slope_normal = slope_normal
			if (slope_normal.y > lower_slope_normal.y):
				lower_slope_normal = slope_normal
		# If the contact normal is facing up, the player is grounded
		if (upper_slope_normal.y >= 0.5):
			is_grounded = true
	# If the player isn't against a wall or something tilting toward them
	if (is_grounded):
		# Then if the player meets a transition and the highest slope normal is not flat
		if (state.get_contact_count() > 1):
			# Reduce friction by dividing by the number of contacts
			player_physics_material.rough = true
			var new_friction = friction
			for i in state.get_contact_count():
				if state.get_contact_local_normal(i).y > 0.1:
					new_friction *= 0.4*(pow(state.get_contact_local_normal(i).y,3))
			player_physics_material.friction = new_friction
		# Else use normal friction
		else:
			player_physics_material.rough = true
			player_physics_material.friction = friction
	# If the player is not grounded, turn off friction
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
	var move2 = Vector2(move.x, move.z) # Convert movement to vector2

	# Get the player velocity
	var vel = state.get_linear_velocity()
	# Remove vertical velocity to get normalized vector of x and z only
	vel.y = 0
	var nvel = vel.normalized() # Get the normalized horizontal player velocity

	# 2D vector to use with angle_to and dot methods
	var nvel2 = Vector2(nvel.x, nvel.z) 

	# If they player is below the speed limit, accept a force in any direction
	if ((nvel.x >= 0 and vel.x < nvel.x*speed_limit) or (nvel.x <= 0 and vel.x > nvel.x*speed_limit) or
	(nvel.z >= 0 and vel.z < nvel.z*speed_limit) or (nvel.z <= 0 and vel.z > nvel.z*speed_limit) or
	(nvel.x == 0 or nvel.z == 0)):
		if (is_grounded):
			move = cross4(move,lower_slope_normal)
			state.add_central_force(move*accel)
		else:
			state.add_central_force(move*air_control)
	# If the player's speed is above the limit, and the movement vector
	# faces away from the velocity vector, add the force
	elif (nvel2.dot(move2) < 0):
		if (is_grounded):
			move = cross4(move,lower_slope_normal)
			state.add_central_force(move*accel)
		else:
			state.add_central_force(move*air_control)
	# If the player's speed is above the limit, and the movement vector
	# is facing the velocity, add the force perpendicular to the
	# velocity; the force is to the left if the angle between the the velocity
	# and movement vectors is negative, and to the right if it's positive.
	else:
		# Get the angle between the velocity and current movement vector
		var angle = nvel2.angle_to(move2)
		# Convert it to degrees
		var theta = rad2deg(angle)

		# If the angle is to the right of the velocity
		if (theta > 0 and theta < 90):
			# Take the cross product between the velocity and the y-axis
			# to get the vector 90 degrees to the right of the velocity
			move = nvel.cross(head.transform.basis.y)
		# If the angle is to the left of the velocity
		elif(theta < 0 and theta > -90):
			# Take the cross product between the y-axis and the velocity
			# to get the vector 90 degrees to the left of the velocity
			move = head.transform.basis.y.cross(nvel)
		if (is_grounded):
			move = cross4(move,lower_slope_normal)
			state.add_central_force(move*accel)
		else:
			state.add_central_force(move*air_control)

	# Shotgun jump test
	if (Input.is_action_just_pressed("fire")):
		var direction: Vector3 = camera.global_transform.basis.z # Opposite of look direction
		state.add_central_force(direction*2500)

func cross4(a,b):
	return a.cross(b).cross(b).cross(b).cross(b)
