extends CharacterBody3D

# Prędkość ruchu postaci
var speed: float = 7.5
const JUMP_VELOCITY: float = 5.15

# Czułość ruchu myszy
const SENS: float = 0.0015

# Podstawowe pole widzenia (FOV) kamery
var BASE_FOV: float = 75.0
const SPRINT_FOV: float = 1.10

# Zmienne grawitacyjne
var gravity: float = 9.0
var air_time: float = 0.0
const BONUS_GRAVITY: float = 4.0

var paused: bool = false

# zmienne do poziomu
var level = 1;
var expirience = 0;
var max_exp = 1000;

# Referencje do węzłów głowy i kamery
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

# Referencja do menu pauzy
@onready var menu = get_node("../CanvasLayer/pausemenu")

# Referencja do ekranu śmierci
@onready var deathscreen = get_node("../CanvasLayer2/deathscreen")

# Zmienne dashowania
@export var dash_speed: float = 40.0
@export var dash_duration: float = 0.08
@export var dash_cooldown: float = 0.75

var is_dashing: bool = false  
var dash_time_left: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var dash_cooldown_timer: float = 0.0
@onready var dodge = $Head/Dodge

# Zmienne strzelania
@export var damage: int = 100
@export var shoot_distance: float = 1000.0
@onready var crosshair = $Head/Camera3D/Crosshair
@onready var gunshot = $Head/GunShot
@onready var reload = $Head/Reload

# Amunicja i przeładowanie
var max_ammo: int = 12
var current_magazine_ammo: int = 6
var max_magazine_ammo: int = 6
var is_reloading: bool = false  
@export var reload_time: float = 2.0
var reload_timer: float = 0.0

# Raycast do wykrywania trafienia
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D

# Zmienne zdrowia
var max_health: int = 100
var current_health: int = max_health

# Zmienne leczenia
var max_heals: int = 3
var remaining_heals: int = max_heals

# Zmienna combo - liczy tylko trafienia
var combo_counter: int = 0  # Licznik trafień

# Zmienna odpowiadająca za szybkostrzelność
@export var fire_rate: float = 0.5  # Czas w sekundach pomiędzy strzałami
var time_since_last_shot: float = 0.0

# Odtwarzacz animacji
@onready var animation_player: AnimationPlayer = $Head/Camera3D/revolver/AnimationPlayer



# Inicjalizacja ustawień
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	crosshair.position.x = get_viewport().size.x / 2 - 16
	crosshair.position.y = get_viewport().size.y / 2 - 16
	raycast.enabled = false
	set_ammo_label()
	set_healthbar_value()
	set_combo_label()

# Obsługuje zdarzenia wejściowe
func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("shoot"):
		if current_magazine_ammo > 0 and not is_reloading and time_since_last_shot >= fire_rate:
			shoot()
			gunshot.play()
		elif current_magazine_ammo == 0:
			print("Brak amunicji! Przeładuj.")

	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENS)
		camera.rotate_x(-event.relative.y * SENS)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(75))

	if Input.is_action_just_pressed("reload") and current_magazine_ammo < max_magazine_ammo and not is_reloading:
		start_reload()

# Proces fizyczny dla ruchu i akcji
func _physics_process(delta: float) -> void:
	time_since_last_shot += delta  # Aktualizacja czasu od ostatniego strzału

	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
	
	if is_dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			is_dashing = false
		else:
			velocity = dash_direction * dash_speed
	else:
		if is_on_floor():
			air_time = 0.0
			velocity.y = max(velocity.y - gravity * delta, -gravity)
		else:
			air_time += delta
			velocity.y -= (gravity + gravity * air_time * BONUS_GRAVITY) * delta

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			air_time = 0.0
		
		var input_dir: Vector2 = Input.get_vector("left", "right", "up", "down")  # Pobierz kierunek wejścia
		var direction: Vector3 = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		if Input.is_action_just_pressed("dash") and direction != Vector3.ZERO and dash_cooldown_timer <= 0.0:
			dodge.play()
			start_dash(direction)
		
		if not is_dashing:
			var target_velocity: Vector3 = direction * speed
			velocity.x = lerp(velocity.x, target_velocity.x, delta * 10.0)
			velocity.z = lerp(velocity.z, target_velocity.z, delta * 10.0)
		else:
			velocity.x = dash_direction.x * dash_speed
			velocity.z = dash_direction.z * dash_speed

	move_and_slide()
	
	var velocity_clamped: float = clamp(velocity.length(), 0.5, speed * 1.5)
	var target_fov: float = BASE_FOV + SPRINT_FOV * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)

	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			finish_reload()

	if Input.is_action_just_pressed("heal") and remaining_heals > 0:
		heal(30)

# Funkcja strzelania
func shoot() -> void:
	if current_magazine_ammo > 0:
		time_since_last_shot = 0.0  # Resetowanie czasu od ostatniego strzału
		raycast.target_position = Vector3(0, 0, -shoot_distance)  # Ustaw cel raycast
		raycast.force_raycast_update()  # Wymuś aktualizację raycastu

		# Odtwórz animację strzału
		animation_player.stop()
		animation_player.play("ArmatureAction")

		if raycast.is_colliding():
			var collider = raycast.get_collider()
			if collider and collider.has_method("take_damage"):
				collider.take_damage(damage)
				# Zwiększ licznik combo po trafieniu
				combo_counter += 1
				set_combo_label()
				print("Combo trafień:", combo_counter)
		else:
			# Zresetuj licznik combo, jeśli nie trafimy
			combo_counter = 0
			set_combo_label()
			print("Chybienie. Combo zresetowane.")

		current_magazine_ammo -= 1
		set_ammo_label()
	else:
		print("Brak amunicji! Przeładuj.")

	raycast.enabled = false

# Rozpocznij dash
func start_dash(direction: Vector3) -> void:
	is_dashing = true
	dash_time_left = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_direction = direction
	velocity = direction * dash_speed

# Rozpocznij przeładowanie
func start_reload() -> void:
	if max_ammo <= 0:
		print("Brak amunicji do przeładowania.")
		return
	
	is_reloading = true
	reload_timer = reload_time
	print("Rozpoczęto przeładowanie")
	animation_player.play("Reload")
	reload.play()

# Zakończ przeładowanie
func finish_reload() -> void:
	var ammo_needed: int = max_magazine_ammo - current_magazine_ammo
	var ammo_to_reload: int = min(ammo_needed, max_ammo)
	current_magazine_ammo += ammo_to_reload
	max_ammo -= ammo_to_reload
	
	is_reloading = false
	set_ammo_label()
	print("Przeładowano. Amunicja w magazynku:", current_magazine_ammo)

# Funkcja do przyjmowania obrażeń
func take_damage(amount: int) -> void:
	current_health -= amount
	set_healthbar_value()
	print("Obrażenia: ", amount, ", Pozostałe życie: ", current_health)
	
	if current_health <= 0:
		die()

# Funkcja do leczenia
func heal(amount: int) -> void:
	if current_health < max_health:
		current_health = min(current_health + amount, max_health)
		remaining_heals -= 1
		print("Leczenie o: ", amount, ", Aktualne życie: ", current_health, ", Pozostałe leczenia: ", remaining_heals)
	else:
		print("Pełne zdrowie! Nie można leczyć.")
	set_healthbar_value()

# Funkcja do śmierci
func die() -> void:
	print("Gracz zginął")
	deathscreen.show_on_death()
	queue_free()

# Aktualizuj etykietę amunicji
func set_ammo_label() -> void:
	$Head/Camera3D/AmmoLabel.text = "%s/%s" % [current_magazine_ammo, max_ammo]

# Aktualizuj pasek zdrowia
func set_healthbar_value() -> void:
	$Head/Camera3D/ProgressBar.value = current_health

# Aktualizuj etykietę combo
func set_combo_label() -> void:
	$Head/Camera3D/ComboLabel.text = "%s" % combo_counter
	
# Otrzymaj doświadczenie
func get_xp() -> void:
	print("dostalem expa!")
	expirience = expirience + 100
	if expirience <= max_exp:
		level_up()
		


#otrzymaj poziom
func level_up() -> void:
	level = level + 1
	max_exp = max_exp + (100*(level-1))
	

func _on_enemy_died():
	print("dostalem expa!")
	expirience = expirience + 100
	if expirience <= max_exp:
		level_up() 