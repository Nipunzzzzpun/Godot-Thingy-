@onready var collision_shape: CollisionShape2D = $CollisionShape2D

const STAND_POS_Y = 14.5
const STAND_HEIGHT = 64.0  # Check your RectangleShape2D -> Size -> y in the Inspector
const CROUCH_HEIGHT = 36.0 # Roughly half of your standing height
