extends CharacterBody2D

const CROUCH_SPEED = 90.0
const WALK_SPEED = 150.0
const RUN_SPEED = 400.0
const JUMP_VELOCITY = -420.0

const ACCELERATION = 900.0
const FRICTION = 1100.0

# UTG Rolling & Slide constants
const ROLL_WINDOW = 0.35         # Max seconds before landing that C counts as a roll
const ROLL_MIN_BOOST = 70.0      # Boost for an early/ok roll
const ROLL_MAX_BOOST = 180.0     # Boost for a near-frame-perfect roll right before landing
const ROLL_BOOST_DURATION = 0.85 # How long the roll speed boost lasts
const SLIDE_DURATION = 4.0       # Retains speed for 4 seconds

# Vault constants
const MAX_VAULT_TILES = 2.0
const TILE_SIZE = 32.0
const VAULT_CLEARANCE_PX = 24.0
const VAULT_FORWARD_BOOST = 280.0
const VAULT_BUFFER_TIME = 0.15

const STAND_POS_Y = 14.5
const STAND_HEIGHT = 64.0
const CROUCH_HEIGHT = 36.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var current_jump_anim := "IdletoJump"
var jump_was_pressed := false
var crouch_was_pressed := false
var was_on_floor := false

# Roll state variables
var roll_primed := false
var roll_prime_time := 0.0
var is_rolling := false
var roll_timer := 0.0
var roll_boost_timer := 0.0
var current_roll_boost := 0.0
var roll_direction := 1.0

# Slide & Vault state variables
var is_sliding := false
var slide_timer := 0.0
var slide_direction := 1.0
var slide_speed := 0.0

var is_vaulting := false
var vault_timer := 0.0
var vault_buffer_timer := 0.0
var vault_facing := 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var ledge_top_ray: RayCast2D = get_node_or_null("LedgeTopRay")

func _physics_process(delta: float) -> void:
	var on_floor_now := is_on_floor()

	# 1. Apply gravity
	if not on_floor_now:
		velocity.y += gravity * delta

	# 2. WASD + Space Input Detection
	var move_left := Input.is_key_pressed(KEY_A)
	var move_right := Input.is_key_pressed(KEY_D)
	var direction := float(int(move_right) - int(move_left))

	var space_pressed := Input.is_key_pressed(KEY_SPACE)
	var jump_pressed := space_pressed or Input.is_key_pressed(KEY_W)
	var jump_just_pressed := jump_pressed and not jump_was_pressed
	jump_was_pressed = jump_pressed

	var crouch_pressed := Input.is_key_pressed(KEY_C)
	var crouch_just_pressed := crouch_pressed and not crouch_was_pressed
	crouch_was_pressed = crouch_pressed

	var is_walking := Input.is_key_pressed(KEY_SHIFT)
	var active_max_run := RUN_SPEED + (current_roll_boost if roll_boost_timer > 0.0 else 0.0)
	var is_running := absf(velocity.x) > WALK_SPEED + 20.0

	# 3. Prime Roll in Mid-Air when pressing C before hitting the ground
	if not on_floor_now and crouch_just_pressed:
		roll_primed = true
		roll_prime_time = 0.0

	if roll_primed and not on_floor_now:
		roll_prime_time += delta
		# Cancel prime if pressed way too early (> 0.35s before landing)
		if roll_prime_time > ROLL_WINDOW:
			roll_primed = false

	# Trigger Roll on the exact frame of landing if primed within the window
	if on_floor_now and not was_on_floor and roll_primed:
		roll_primed = false
		is_rolling = true
		is_sliding = false
		roll_timer = 0.45 # Matches length of Rolling animation
		roll_boost_timer = ROLL_BOOST_DURATION

		# Closer to the ground (smaller roll_prime_time) = bigger speed boost!
		var precision := 1.0 - clampf(roll_prime_time / ROLL_WINDOW, 0.0, 1.0)
		current_roll_boost = lerpf(ROLL_MIN_BOOST, ROLL_MAX_BOOST, precision)

		roll_direction = signf(velocity.x) if absf(velocity.x) > 10.0 else (-1.0 if animated_sprite.flip_h else 1.0)
		velocity.x = roll_direction * (RUN_SPEED + current_roll_boost)
		animated_sprite.play("Rolling")

	# Update active Roll & Roll Boost timers
	if roll_boost_timer > 0.0:
		roll_boost_timer -= delta
		if roll_boost_timer <= 0.0:
			current_roll_boost = 0.0

	if is_rolling:
		roll_timer -= delta
		velocity.x = roll_direction * (RUN_SPEED + current_roll_boost)
		if roll_timer <= 0.0 or not on_floor_now or is_on_wall():
			is_rolling = false
			# UTG Slide Transfer: keeping C held after rolling transitions straight into a boosted slide!
			if crouch_pressed and on_floor_now and not is_on_wall():
				is_sliding = true
				slide_timer = SLIDE_DURATION
				slide_direction = roll_direction
				slide_speed = absf(velocity.x)

	# 4. Point LedgeTopRay toward facing direction
	var facing := -1.0 if animated_sprite.flip_h else 1.0
	if ledge_top_ray:
		ledge_top_ray.position.x = absf(ledge_top_ray.position.x) * facing

	# 5. Vault Buffer & Trigger
	if space_pressed:
		if jump_just_pressed:
			vault_buffer_timer = VAULT_BUFFER_TIME
	else:
		vault_buffer_timer = 0.0

	if vault_buffer_timer > 0.0:
		vault_buffer_timer -= delta

	var did_vault := false
	if (vault_buffer_timer > 0.0 or (space_pressed and not on_floor_now)) and can_vault():
		start_vault(facing)
		vault_buffer_timer = 0.0
		did_vault = true

	if is_vaulting:
		vault_timer -= delta
		velocity.x = vault_facing * maxf(absf(velocity.x), VAULT_FORWARD_BOOST)
		if vault_timer <= 0.0 or (on_floor_now and velocity.y >= 0.0):
			is_vaulting = false

	# 6. Slide Check (Running + holding C retains speed for 4 seconds)
	if crouch_just_pressed and on_floor_now and is_running and not is_sliding and not is_rolling:
		is_sliding = true
		slide_timer = SLIDE_DURATION
		slide_direction = signf(velocity.x)
		slide_speed = absf(velocity.x)

	if is_sliding:
		slide_timer -= delta
		if not crouch_pressed or slide_timer <= 0.0 or not on_floor_now or is_on_wall():
			is_sliding = false
		else:
			velocity.x = slide_direction * slide_speed

	# 7. Normal Jump (preserves roll speed boost if jumping out of a roll/slide!)
	if jump_just_pressed and on_floor_now and not did_vault and not is_vaulting:
		is_sliding = false
		is_rolling = false
		roll_primed = false
		velocity.y = JUMP_VELOCITY
		current_jump_anim = "RuntoJump" if is_running else "IdletoJump"
		animated_sprite.play(current_jump_anim)

	# 8. Normal Horizontal Movement (when not rolling, sliding, or mid-vault)
	var is_crouching := crouch_pressed and on_floor_now and not is_sliding and not is_rolling

	if not is_sliding and not is_vaulting and not is_rolling:
		var target_speed := active_max_run
		if is_crouching:
			target_speed = CROUCH_SPEED
		elif is_walking:
			target_speed = WALK_SPEED

		if direction != 0:
			velocity.x = move_toward(velocity.x, direction * target_speed, ACCELERATION * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, FRICTION * delta)

	# 9. Update hitbox and animations
	update_hitbox(is_crouching or is_sliding or is_rolling)
	update_animations(direction, is_crouching)

	was_on_floor = on_floor_now
	move_and_slide()

func can_vault() -> bool:
	if not ledge_top_ray or is_vaulting:
		return false
	if not ledge_top_ray.is_colliding():
		return false

	var ledge_surface_y := ledge_top_ray.get_collision_point().y
	var ray_start_y := ledge_top_ray.global_position.y
	if ledge_surface_y <= ray_start_y + 2.0:
		return false

	var player_feet_y := global_position.y + STAND_POS_Y + (STAND_HEIGHT / 2.0)
	var height_to_climb := player_feet_y - ledge_surface_y
	var max_vault_px := MAX_VAULT_TILES * TILE_SIZE

	return height_to_climb > 12.0 and height_to_climb <= max_vault_px

func start_vault(facing: float) -> void:
	is_vaulting = true
	is_sliding = false
	is_rolling = false
	roll_primed = false
	vault_timer = 0.35
	vault_facing = facing

	var ledge_surface_y := ledge_top_ray.get_collision_point().y
	var player_feet_y := global_position.y + STAND_POS_Y + (STAND_HEIGHT / 2.0)
	var max_vault_px := MAX_VAULT_TILES * TILE_SIZE

	var height_to_climb := clampf(player_feet_y - ledge_surface_y, 0.0, max_vault_px)
	var total_launch_height := height_to_climb + VAULT_CLEARANCE_PX

	velocity.y = -sqrt(2.0 * gravity * total_launch_height)
	velocity.x = facing * maxf(absf(velocity.x), VAULT_FORWARD_BOOST)
	animated_sprite.play("Vaulting")

func update_hitbox(is_low: bool) -> void:
	var shape := collision_shape.shape as RectangleShape2D
	if is_low:
		shape.size.y = CROUCH_HEIGHT
		collision_shape.position.y = STAND_POS_Y + (STAND_HEIGHT - CROUCH_HEIGHT) / 2.0
	else:
		shape.size.y = STAND_HEIGHT
		collision_shape.position.y = STAND_POS_Y

func update_animations(direction: float, is_crouching: bool) -> void:
	if not is_sliding and not is_vaulting and not is_rolling:
		if direction > 0:
			animated_sprite.flip_h = false
		elif direction < 0:
			animated_sprite.flip_h = true

	var current_speed := absf(velocity.x)

	if is_vaulting:
		animated_sprite.play("Vaulting")
		return

	if is_rolling:
		animated_sprite.play("Rolling")
		return

	if is_sliding:
		animated_sprite.play("Sliding")
		return

	if not is_on_floor():
		animated_sprite.play(current_jump_anim)
		return

	if is_crouching:
		animated_sprite.play("Crouchwalk")
		if current_speed <= 10.0:
			animated_sprite.pause()
	elif current_speed > WALK_SPEED + 20.0:
		animated_sprite.play("Running")
	elif current_speed > 10.0:
		animated_sprite.play("Walking")
	else:
		animated_sprite.play("Idle")
