extends RigidBody3D

### Use the Jolt physics engine

#DevNotes to-do:
# Separate concerns for mouse and movement input handling, collider and mesh resizing
# Add dash with set velocity?
# Newton's third law eventually breaks. Wondering whether it's a physics engine bug.

### Global

## Whether to draw the debug lines for forces
@export var debug_lines: bool
## Whether to print normals at the points of contact with the player capsule
@export var debug_contact_normals: bool
## Whether to print details for groundedness checks
@export var debug_groundedness: bool
var is_grounded: bool  # Whether the player is considered to be touching a walkable slope
@onready var capsule = $CollisionShape3D.shape  # Capsule collision shape of the player
@onready var capsule_mesh = $MeshInstance3D.mesh # Capsule mesh shape
@onready var camera = $"../Head/Pitch/Camera3D"  # Camera3D node
@onready var head = $"../Head"  # y-axis rotation node (look left and right)

### Input vars
@onready var pitch = $"../Head/Pitch"  # x-axis rotation node (look up and down)

### Integrate forces vars

## Player acceleration force.
@export var accel: int
## Jump force multiplier.
@export var jump: int 
## Air control multiplier.
@export var air_control: int
## How quickly to scale movement toward a turning direction. Lower is more. 
@export_range(15, 120, 1) var turning_scale: float
## Mouse sensetivity. Default: 0.05.
@export var mouse_sensitivity: float = 0.05
## Defines the steepest walkable slope. Lower is steeper. Default: 0.5.
@export_range(0, 1, 0.01) var walkable_normal: float
## The rate at which the player moves in or out of the crouching position. High values may cause physics glitches.
@export_range(2, 20) var speed_to_crouch: int
## Default speed limit of the player. Default: 8.
@export var speed_limit: float = 8
## Speed to move at while crouching. Default: 4.
@export var crouching_speed_limit: float = 4
## Speed to move at while sprinting. Default: 12.
@export var sprinting_speed_limit: float = 12
## Amount to divide the friction by when not grounded (prevents sticking to walls that may come from air control). Default: 3.
@export var friction_divider = 3
var steepest_slope_normal: Vector3 # Stores the lowest (steepest) normal of the contact with the player collider
var shallowest_slope_normal: Vector3  # Stores the highest (flattest) normal of the contact with the player collider
var slope_normal: Vector3  # Stores normals of contact points for iteration
var contacted_body: RigidBody3D  # Rigid body the player is currently contacting, if there is one
var player_physics_material = load("res://Physics/player.tres")
var local_friction = player_physics_material.friction  # Editor friction value
var is_landing: bool = true  # Whether the player has jumped and let go of jump
var is_jumping: bool = false  # Whether the player has jumped
## Stores preference for the delta time before the player can jump again. Default: 0.1.
@export_range(0.01,1,0.01) var JUMP_THROTTLE: float  = 0.1
var jump_throttle: float  # Variable used with jump throttling calculations
## Downward force multiplier to apply when letting go of space while jumping, in order to assist with landing. Default: 1.5.
@export var landing_assist: float = 1.5
## Amount of force to stop sliding with (alternative to friction). Default: 3.
@export_range(0.1,100,0.1) var anti_slide_force: float = 3
## Number of hitscans to use around the base of the player capsule to detect groundedness.
@export var groundedness_hitscan_count: int = 12

### Physics process vars
var original_height: float
var crouching_height: float
var current_speed_limit: float  # Current speed limit to use. For standing or crouching.
var posture  # Current posture state
enum { WALKING, CROUCHING, SPRINTING }  # Possible values for posture

### Misc
var ld = preload("res://Scripts//DrawLine3D.gd").new()

func draw_arrow(pos1: Vector3, pos2: Vector3, color = Color.WHITE_SMOKE, persist_seconds = 0):
	ld.line(pos1, pos2, color, persist_seconds)
	ld.point(pos1, 0.0075, color, persist_seconds)

### Godot notification functions ###
func _ready():
	# Get capsule variables
	original_height = capsule.height
	crouching_height = capsule.height / 2
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)  # Capture and hide mouse
	add_child(ld)  # Add line drawer


func _input(event):
	# Player look
	if event is InputEventMouseMotion:
		head.rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		pitch.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		pitch.rotation.x = clamp(pitch.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	# Capture and release mouse
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)  # Free the mouse
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


var is_done_shrinking: bool  # temporary # Whether the player is currently shrinking towards being crouched
func _physics_process(delta):
	# Keep camera with player
	head.position = self.position + Vector3.UP * capsule.height / 2

### Player posture FSM
	if Input.is_action_pressed("crouch"):
		posture = CROUCHING
	elif Input.is_action_pressed("sprint"):
		posture = SPRINTING
	else:
		posture = WALKING

### Groundedness raycasts
	is_grounded = false
	# Define raycast info used with detecting groundedness
	var raycast_list = Array()  # List of raycasts used with detecting groundedness
	var bottom = Vector3(0, 0.2, 0)  # Distance down from start to fire the raycast to
	var start = (capsule.height / 2) - 0.2  # Start point down from the center of the player to start the raycast
	var edge_vector = Vector3(0, 0, capsule.radius - 0.1) # Initial vector toward the edge of the capsule
	# Get world state for collisions
	var direct_state = get_world_3d().direct_space_state
	raycast_list.clear()
	
	## Create raycasts around the player capsule. They begin towards the edge of the radius, and shoot from just
	## below the capsule to just below the bottom bounds of the capsule, with one raycast down from the center.
	# Get the starting location for the hitscans
	var location: Vector3 = self.position
	location.y -= start
	# Create the center raycast
	raycast_list.append([location, location - bottom])
	# Create the raycasts out from the center of the capsule
	for i in groundedness_hitscan_count:
		var working_location = location
		# The vector is rotated around the y-axis before applying to the edge vector to the centered point
		working_location += edge_vector.rotated(Vector3(0, 1, 0), deg_to_rad((i + 1) * 360.0 / groundedness_hitscan_count))
		# Subtract from the working location's vertical axis to get the ending point
		var end_point = working_location - bottom
		# Add an array, containing the two points for this iteration, to the list of raycasts
		raycast_list.append([working_location, end_point])
	# Check each raycast for collision, ignoring the capsule itself
	for array in raycast_list:
		var params = PhysicsRayQueryParameters3D.new()
		params.from = array[0]
		params.to = array[1]
		params.exclude = [self]
		if debug_lines: ld.line(array[0], array[1], Color.CHARTREUSE, 0)
		var collision = direct_state.intersect_ray(params)
		# The player is grounded if any of the raycasts hit
		if collision and is_walkable(collision.normal.y):
			is_grounded = true
	if debug_groundedness: print("Grounded Hitscans: "+str(is_grounded))
	

### Sprinting & Crouching
	var capsule_scale = delta * speed_to_crouch  # Amount to change capsule height up or down
	var move_camera = delta / 2 * speed_to_crouch  # Amount to move camera while crouching
	match posture:
		SPRINTING:
			current_speed_limit = sprinting_speed_limit
			grow_capsule(is_done_shrinking, capsule_scale, move_camera)
		CROUCHING:  # Shrink
			current_speed_limit = crouching_speed_limit
			if capsule.height > crouching_height:
				capsule.height -= capsule_scale
				capsule_mesh.height -= capsule_scale
			elif is_done_shrinking == false:
				## Adding a force to work around some physics glitches for the moment
				#var look_direction = head.transform.basis.z
				#self.apply_central_force(look_direction * mass * 100)
				is_done_shrinking = true
		WALKING:  # Grow
			current_speed_limit = speed_limit
			grow_capsule(is_done_shrinking, capsule_scale, move_camera)

	# Setup jump throttle for integrate_forces
	if is_jumping or is_landing:
		jump_throttle -= delta
	else:
		jump_throttle = JUMP_THROTTLE


func _integrate_forces(state):
	steepest_slope_normal = Vector3(0, 1, 0)
	shallowest_slope_normal = Vector3(0, -1, 0)
	contacted_body = null  # Rigidbody
	# Velocity of the Rigidbody the player is contacting
	var contacted_body_vel_at_point = Vector3()

### Grounding, slopes, & rigidbody contact point
	# If the player body is contacting something
	var shallowest_contact_index: int = -1
	
	if state.get_contact_count() > 0:
		# Iterate over the capsule contact points and get the steepest/shallowest slopes
		for i in state.get_contact_count():
			slope_normal = state.get_contact_local_normal(i)
			if slope_normal.y < steepest_slope_normal.y:  # Lower normal means steeper slope
				steepest_slope_normal = slope_normal
			if slope_normal.y > shallowest_slope_normal.y:
				shallowest_slope_normal = slope_normal
				shallowest_contact_index = i
		if debug_contact_normals: print("Steepest normal: "+str(steepest_slope_normal))
		if debug_contact_normals: print("Shallowest normal: "+str(shallowest_slope_normal))
		#### If the steepest slope contacted is more shallow than the walkable_normal, the player is grounded
		####if is_walkable(steepest_slope_normal.y):
			####is_grounded = true
		# If the shallowest slope normal is walkabe, the player is grounded #### Else if the shallowest slope normal is not walkable, the player is not grounded
		if is_walkable(shallowest_slope_normal.y):
			is_grounded = true
		if debug_groundedness: print("Grounded Contacts: "+str(is_grounded))
		# If a rigidbody is contacted, get the velocity at contact to be used with relative velocity calculations
		if shallowest_contact_index >= 0:
			var contact_position = state.get_contact_collider_position(0)  # coords of the contact point from center of contacted body
			var collisions = get_colliding_bodies()
			var rb_collision_idx = null # rigidbody collision index
			if collisions.size() > 0:
				for collision_idx in collisions.size():
					if collisions[collision_idx].get_class() == "RigidBody3D":
						rb_collision_idx = collision_idx
			# Only use the relative velocity of the contacted body if it's considered walkable
			## This prevents the relative velocity calculations from adding continual sideways force to an object
			if (rb_collision_idx != null and is_walkable(steepest_slope_normal.y)):
				contacted_body = collisions[rb_collision_idx]
				contacted_body_vel_at_point = state.get_contact_collider_velocity_at_position(rb_collision_idx)
				#contacted_body_vel_at_point = get_contacted_body_velocity_at_point(
				#	contacted_body, contact_position
				#)

### Jumping: Should allow the player to jump, and hold jump to jump again if they become grounded after a throttling period
	var has_walkable_contact: bool = (
		state.get_contact_count() > 0 and is_walkable(shallowest_slope_normal.y)
	)  # Different from is_grounded
	# If the player is trying to jump, the throttle expired, the player is grounded, and they're not already jumping, jump
	# Check for is_jumping is because contact still exists at the beginning of a jump for more than one physics frame
	if (
		Input.is_action_pressed("jump")
		and jump_throttle < 0
		and has_walkable_contact
		and not is_jumping
	):
		state.apply_central_impulse(Vector3(0, 1, 0) * jump)
		is_jumping = true
		is_landing = false
	# Apply a downward force once if the player lets go of jump to assist with landing
	if Input.is_action_just_released("jump"):
		if is_landing == false:  # Only apply the landing assist force once
			is_landing = true
			if not has_walkable_contact:
				state.apply_central_impulse(Vector3(0, -1, 0) * landing_assist)
	# If the player becomes grounded, they're no longer considered to be jumping
	if has_walkable_contact:
		is_jumping = false

### Movement
	var move = relative_input()  # Get movement vector relative to player orientation
	var move2 = Vector2(move.x, move.z)  # Convert movement for Vector2 methods

	set_friction()

	# Get the player velocity, relative to the contacting body if there is one
	var vel = Vector3()
	if is_grounded:
		## Keep vertical velocity if grounded. vel will be normalized below
		## accounting for the y value, preventing faster movement on slopes.
		vel = state.get_linear_velocity()
		vel -= contacted_body_vel_at_point
	else:
		## Remove y value of velocity so only horizontal speed is checked in the air.
		## Without this, the normalized vel causes the speed limit check to
		## progressively limit the player from moving horizontally in relation to vertical speed.
		vel = Vector3(state.get_linear_velocity().x, 0, state.get_linear_velocity().z)
		vel -= Vector3(contacted_body_vel_at_point.x, 0, contacted_body_vel_at_point.z)
	# Get a normalized player velocity
	var nvel = vel.normalized()
	var nvel2 = Vector2(nvel.x, nvel.z)  # 2D velocity vector to use with angle_to and dot methods

	## If below the speed limit, or above the limit but facing away from the velocity,
	## move the player, adding an assisting force if turning. If above the speed limit,
	## and facing the velocity, add a force perpendicular to the velocity and scale
	## it based on where the player is moving in relation to the velocity.
	# Get the angle between the velocity and current movement vector and convert it to degrees
	var angle = nvel2.angle_to(move2)
	var theta = rad_to_deg(angle)  # Angle between 2D look and velocity vectors
	var is_below_speed_limit: bool = is_below_speed_limit(vel)
	var is_facing_velocity: bool = nvel2.dot(move2) >= 0
	var direction: Vector3  # vector to be set 90 degrees either to the left or right of the velocity
	var scale: float  # Scaled from 0 to 1. Used for both turn assist interpolation and vector scaling
	# If the angle is to the right of the velocity
	if theta > 0 and theta < 90:
		direction = nvel.cross(head.transform.basis.y)  # Vecor 90 degrees to the right of velocity
		scale = clamp(theta / turning_scale, 0, 1)  # Turn assist scale
	# If the angle is to the left of the velocity
	elif theta < 0 and theta > -90:
		direction = head.transform.basis.y.cross(nvel)  # Vecor 90 degrees to the left of velocity
		scale = clamp(-theta / turning_scale, 0, 1)
	# Prevent continuous sliding down steep walkable slopes when the player isn't moving. Could be made better with
	# debouncing because too high of a force also affects stopping distance noticeably when not on a slope.
	if move == Vector3(0, 0, 0) and is_grounded:
		move = -vel / (mass * 100 / anti_slide_force)
		move(move, state)
	# If not pushing into an unwalkable slope
	elif steepest_slope_normal.y > walkable_normal:
		# If the player is below the speed limit, or is above it, but facing away from the velocity
		if is_below_speed_limit or not is_facing_velocity:
			# Interpolate between the movement and velocity vectors, scaling with turn assist sensitivity
			move = move.lerp(direction, scale)
		# If the player is above the speed limit, and looking within 90 degrees of the velocity
		else:
			move = direction  # Set the move vector 90 to the right or left of the velocity vector
			move *= scale  # Scale the vector. 0 if looking at velocity, up to full magnitude if looking 90 degrees to the side.
		move(move, state)
	# If pushing into an unwalkable slope, move with unscaled movement vector. Prevents turn assist from pushing the player into the wall.
	elif is_below_speed_limit:
		move(move, state)
### End movement

	# Shotgun jump test
	if Input.is_action_just_pressed("fire"):
		var dir: Vector3 = camera.global_transform.basis.z  # Opposite of look direction
		state.apply_central_force(dir * 700)


### Functions ###
# Gets the velocity of a contacted rigidbody at the point of contact with the player capsule
'''
func get_contacted_body_velocity_at_point(contacted_body: RigidBody3D, contact_position: Vector3):
	# Global coordinates of contacted body
	var body_position = contacted_body.transform.origin
	# Global coordinates of the point of contact between the player and contacted body
	var global_contact_position = body_position + contact_position
	# Calculate local velocity at point (cross product of angular velocity and contact position vectors)
	#print(contacted_body.get_angular_velocity())
	var local_vel_at_point = contacted_body.get_angular_velocity().cross(
		global_contact_position - body_position - body_position
	)
	# Add the current velocity of the contacted body to the velocity at the contacted point
	return contacted_body.get_linear_velocity() + local_vel_at_point
'''


# Return 4 cross products of b with a
func cross4(a, b):
	return a.cross(b).cross(b).cross(b).cross(b)


# Whether a slope is walkable
func is_walkable(normal: float):
	return normal >= walkable_normal  # Lower normal means steeper slope


# Whether the player is below the speed limit in the direction they're traveling
func is_below_speed_limit(vel):
	return vel.length() < current_speed_limit 


# Move the player
func move(move, state):
	var draw_start = self.position - Vector3(0, capsule.height / 4, 0) + move  # debug
	if is_grounded:
		var use_normal = Vector3(0,1,0) # For no slope
		var closest_contact_idx = null # The index of the contact point closest to the players intended movement vector
		# If a contact or contacts exist(s), use the normal at the contact point closest to the player's intended movement vector (for slope detection)
		if state.get_contact_count() > 0:
			var smallest_angle = null
			for i in state.get_contact_count():
				var origin_to_contact: Vector3 = state.get_contact_local_position(i) - self.transform.origin
				var angle = origin_to_contact.angle_to(relative_input())
				if closest_contact_idx == null or smallest_angle == null or angle < smallest_angle:
					closest_contact_idx = i
					smallest_angle = angle
		if closest_contact_idx != null:
			use_normal = state.get_contact_local_normal(closest_contact_idx)
			
		move = cross4(move, use_normal)  # Get slope to move along based on contact
		if debug_lines:
			draw_arrow(draw_start, draw_start + move * capsule.radius, Color(1, 0, 0), 3)  # debug
		state.apply_central_force(move * accel)
		# Account for equal and opposite reaction when contacting a RigidBody
		if contacted_body != null:
			pass #contacted_body.apply_force(state.get_contact_collider_position(0), move * -accel)
	else:
		if debug_lines:
			draw_arrow(draw_start, draw_start + move * capsule.radius, Color(0, 0, 1), 3)  # debug
		state.apply_central_force(move * air_control)


# Set player friction
func set_friction():
	player_physics_material.friction = local_friction
	# If moving or not grounded, reduce friction
	if not is_grounded:
		player_physics_material.friction = local_friction / friction_divider


# Get movement vector based on input, relative to the player's head transform
func relative_input():
	# Initialize the movement vector
	var move = Vector3()
	# Get cumulative input on axes
	var input = Vector3()
	input.z += int(Input.is_action_pressed("move_forward"))
	input.z -= int(Input.is_action_pressed("move_backward"))
	input.x += int(Input.is_action_pressed("move_right"))
	input.x -= int(Input.is_action_pressed("move_left"))
	# Add input vectors to movement relative to the direction the head is facing
	move += input.z * -head.transform.basis.z
	move += input.x * head.transform.basis.x
	# Normalize to prevent stronger diagonal forces
	return move.normalized()


# Grow the capsule toward the standing height
func grow_capsule(is_done_shrinking, capsule_scale, move_camera):
	is_done_shrinking = false
	if capsule.height < original_height:
		capsule.height += capsule_scale
		capsule_mesh.height += capsule_scale
