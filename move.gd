extends RigidBody

# Use the GodotPhysics physics engine

#DevNotes to-do:
	# Change values for capsule raycasts to be calculated based on height/radius
	# Use raycast towards movement direction to determine which normals to use for movement cross products.
	# Add crouch. Crouch during jump only while space is held to make landing accurately easier.
	# Fix input to cancel opposing inputs instead of one overriding.

### Integrate forces vars
export var accel: int # 300 # Player acceleration force
export var jump: int # 25 # Jump force multiplier
export var air_control: int # 20 # Air control multiplier
export var mouse_sensitivity: = 0.05 # 0.05 
export var speed_limit: float # 10 # Default speed limit of the player while grounded
export(float, 0, 1, 0.01) var walkable_normal # 0.35 # Walkable slope. Lower is steeper
var friction_divider = 8 # Amount to divide the friction by while moving or not grounded
var upper_slope_normal: Vector3 # Stores the lowest (steepest) slope normal
var lower_slope_normal: Vector3 # Stores the highest (flattest) slope normal
var contacted_body: RigidBody # Rigid body the player is currently contacting, if there is one

var player_physics_material = load("res://Physics/player.tres")
var local_friction = player_physics_material.friction # Editor friction value
var is_landing: bool = false # Whether the player has jumped and let go of jump
var slope_normal: Vector3 # Stores normals of contact points for iteration

### Process vars
onready var head = $Head # y-axis rotation node (look left and right)
onready var pitch = $Head/Pitch # x-axis rotation node (look up and down)
onready var camera = $Head/Pitch/Camera # Camera node

### Physics process vars
var is_grounded: bool # Whether the player is considered to be touching a walkable slope
var raycast_list = Array() # List of raycasts used with detecting groundedness
var start = 1.2 # Start point down from the top of the player to start the raycast
var bottom = 0.29 # Distance down from start to fire the raycast to
# Cardinal vector distance
var cv_dist = 0.45
# Ordinal vector distance
# Added to 2 cardinal vectors to result in a diagonal with the same magnitude of the cardinal vectors
var ov_dist= cv_dist/sqrt(2)

#Input vars
enum mouse {freed = 0, taken = 2}


# On load
func _ready():
	Input.set_mouse_mode(mouse.taken) # Capture and hide mouse
	
func _input(event):
	# Player look
	if event is InputEventMouseMotion:
		head.rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		pitch.rotate_x(deg2rad(-event.relative.y * mouse_sensitivity))
		pitch.rotation.x = clamp(pitch.rotation.x, deg2rad(-90), deg2rad(90))
	# Capture and release mouse
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == mouse.taken:
			Input.set_mouse_mode(mouse.freed) # Free the mouse
		else:
			Input.set_mouse_mode(mouse.taken)
			
func _physics_process(_delta):
	var this = get_colliding_bodies()
	# Get world state for collisions
	var direct_state = get_world().direct_space_state
	raycast_list.clear()
	is_grounded = false
	# Create 9 raycasts around the player capsule.
	# They begin towards the edge of the radius and shoot from just
	# below the capsule, to just below the bottom bound of the capsule,
	# with one raycast down from the center.
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
		# The player is grounded if any of the raycasts hit
		if (collision and (collision.normal.y >= walkable_normal)):
			is_grounded = true

func _integrate_forces(state):
	upper_slope_normal = Vector3(0,1,0)
	lower_slope_normal = Vector3(0,-1,0)
	contacted_body = null # Rigidbody
	# Velocity of the Rigidbody the player is contacting
	var contacted_body_vel_at_point = Vector3()
	
### Grounding and slopes
	# If the player body is contacting something
	var shallowest_contact_index: int = -1
	if (state.get_contact_count() > 0):
		# Iterate over the capsule contact points and get the steepest/shallowest slopes
		for i in state.get_contact_count():
			slope_normal = state.get_contact_local_normal(i)
			if (slope_normal.y < upper_slope_normal.y): # Lower normal means steeper slope
				upper_slope_normal = slope_normal
			if (slope_normal.y > lower_slope_normal.y):
				lower_slope_normal = slope_normal
				shallowest_contact_index = i
		# If the steepest slope contacted is more shallow than the walkable_normal, the player is grounded
		if (is_walkable(upper_slope_normal.y)):
			is_grounded = true
			# If the shallowest contact index exists, get the velocity of the body at the contacted point
			if (shallowest_contact_index >= 0):
				var contact_position = state.get_contact_collider_position(0) # coords of the contact point from center of contacted body
				var collisions = get_colliding_bodies()
				if (collisions.size() > 0 and collisions[0].get_class() == "RigidBody"):
					contacted_body = collisions[0]
					contacted_body_vel_at_point = get_contacted_body_velocity_at_point(contacted_body, contact_position)
					#print(contacted_body_vel_at_point)

### Jumping
	# If the player tried to jump, and is grounded, apply an upward force times the jump multiplier
	if (Input.is_action_just_pressed("jump")):
		if (is_grounded):
			state.apply_central_impulse(Vector3(0,1,0) * jump)
			is_landing = false
	# Apply a downward force once if the player lets go of jump to assist with landing
	if (not is_grounded) and Input.is_action_just_released("jump"):
		if (is_landing == false):
			var jump_fraction = jump / 7
			state.apply_central_impulse(Vector3(0,-1,0) * jump_fraction)
			is_landing = true

### Movement
	var move = relative_input() ## Maybe move this into _input() so it's more efficient
	var move2 = Vector2(move.x, move.z) # Convert movement for Vector2 methods
	
	set_friction(move)
	
	# Get the player velocity relative to the contacting body
	#print(state.get_linear_velocity())
	var vel = Vector3()
	if is_grounded:
		# Keep vertical velocity if grounded. vel will be normalized below 
		# accounting for the y value, preventing faster movement on slopes.
		vel = state.get_linear_velocity()
		vel -= contacted_body_vel_at_point
	else:
		# Remove y value of velocity so only horizontal speed is checked in the air.
		# Without this, the normalized vel causes the speed limit check to
		# progressively limit the player from moving horizontally in relation to vertical speed.
		vel = Vector3(state.get_linear_velocity().x,0,state.get_linear_velocity().z)
		vel -= Vector3(contacted_body_vel_at_point.x,0,contacted_body_vel_at_point.z)
	# Get a normalized player velocity 
	var nvel = vel.normalized()
	var nvel2 = Vector2(nvel.x, nvel.z) # 2D velocity vector to use with angle_to and dot methods

	# If they player is below the speed limit, accept a force in any direction
	if (is_below_speed_limit(nvel,vel)):
		move(move,state)
	# If the player's speed is above the limit, and the movement vector
	# faces away from the velocity vector, add the force
	elif (nvel2.dot(move2) < 0):
		move(move,state)
	# If the player's speed is above the limit, and the movement vector
	# is facing the velocity, add the force perpendicular to the
	# velocity; the force is to the left if the angle between the the velocity
	# and movement vectors is negative, and to the right if it's positive.
	else:
		# Get the angle between the velocity and current movement vector and convert it to degrees
		var angle = nvel2.angle_to(move2)
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
		move(move,state)
### End movement

	# Shotgun jump test
	if (Input.is_action_just_pressed("fire")):
		var direction: Vector3 = camera.global_transform.basis.z # Opposite of look direction
		state.add_central_force(direction*7500)

# Gets the velocity of a contacted rigidbody at the point of contact with the player capsule
func get_contacted_body_velocity_at_point(contacted_body, contact_position):
	# Global coordinates of contacted body
	var body_position = contacted_body.transform.origin
	# Global coordinates of the point of contact between the player and contacted body
	var global_contact_position = body_position + contact_position
	# Calculate local velocity at point (cross product of angular velocity and contact position vectors)
	var local_vel_at_point = contacted_body.get_angular_velocity().cross(global_contact_position - body_position)
	# Add the current velocity of the contacted body to the velocity at the contacted point
	return contacted_body.get_linear_velocity() + local_vel_at_point

# Return 4 cross products of b with a
func cross4(a,b):
	return a.cross(b).cross(b).cross(b).cross(b)
	
# Whether a slope is walkable
func is_walkable(normal):
	return (normal >= walkable_normal) # Lower normal means steeper slope

# Whether the player is below the speed limit in the direction they're traveling
func is_below_speed_limit(nvel,vel):
	return ((nvel.x >= 0 and vel.x < nvel.x*speed_limit) or (nvel.x <= 0 and vel.x > nvel.x*speed_limit) or
		(nvel.z >= 0 and vel.z < nvel.z*speed_limit) or (nvel.z <= 0 and vel.z > nvel.z*speed_limit) or
		(nvel.x == 0 or nvel.z == 0))

# Move the player
func move(move,state):
	if is_grounded:
		move = cross4(move,lower_slope_normal) # Get slope to move along based on contact
		state.add_central_force(move * accel)
		# Account for equal and opposite reaction when accelerating on ground
		if (contacted_body != null):
			contacted_body.add_force(move * -accel,state.get_contact_collider_position(0))
	else:
		state.add_central_force(move * air_control)

# Set player friction
func set_friction(move):
	player_physics_material.friction = local_friction
	if ((move != Vector3(0,0,0)) or (not is_grounded)):
		player_physics_material.friction = local_friction/friction_divider
		
# Get movement vector based on input, relative to the player's camera transform
func relative_input():
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
	return move
