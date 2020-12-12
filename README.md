Code of interest in [move.gd](https://github.com/FreeFlyFall/RigidBodyController/blob/master/move.gd)

# RigidBodyController
The beginnings of a first person rigidbody character controller in Godot. Some of the benefits:
- Pushing, being pushed by, and riding other objects with no extra code
- Shotgun jumping and air controls
- Movement acceleration and velocity limits
    - Velocity limits only apply to movement input. Outside forces, such as pushes or shotgun jumping can force the player above the velocity limit.
    The player can oppose these forces and slow down or move sideways, but can't add to the speed in the direction which is over the velocity limit.
- Smooth movement transitions - inherent friction and inertia
- Easy walking on slopes

[Reddit Video](https://www.reddit.com/r/godot/comments/grxg1e/physics_based_character_controller/)
