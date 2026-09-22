extends RefCounted

const WeaponSoundProfileScript = preload("res://src/client/presentation/weapon_sound_profile.gd")
static func _synthesize_weapon(profile, variant: int) -> AudioStreamWAV:
	var mix_rate := 22050
	var tier: int = profile.power_tier
	var duration: float = 0.10 + tier * 0.012
	match profile.family:
		WeaponSoundProfileScript.FAMILY_AUTOMATIC:
			duration = 0.064 + tier * 0.008
		WeaponSoundProfileScript.FAMILY_HEAVY:
			duration = 0.17 + tier * 0.026
		WeaponSoundProfileScript.FAMILY_RAIL:
			duration = 0.115 + tier * 0.014
		WeaponSoundProfileScript.FAMILY_SCATTER:
			duration = 0.135 + tier * 0.018
		WeaponSoundProfileScript.FAMILY_BEAM_PULSE:
			duration = 0.14 + tier * 0.015
		WeaponSoundProfileScript.FAMILY_BEAM_REPEATER:
			duration = 0.078 + tier * 0.009
		WeaponSoundProfileScript.FAMILY_BEAM_LANCE:
			duration = 0.21 + tier * 0.028
	var sample_count := maxi(roundi(duration * mix_rate), 1)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var seed := absi(hash("%s:%d" % [profile.cache_key(), variant])) + 1
	var noise_state := seed % 2147483647
	var primary_phase := 0.0
	var secondary_phase := 0.0
	var sub_phase := 0.0
	var peak := 0.001
	for index in sample_count:
		var progress := float(index) / float(sample_count)
		noise_state = int(posmod(noise_state * 1103515245 + 12345, 2147483647))
		var noise := float(noise_state) / 1073741823.5 - 1.0
		var start_hz := 820.0
		var end_hz := 115.0
		if profile.family == WeaponSoundProfileScript.FAMILY_AUTOMATIC:
			start_hz = 1040.0
			end_hz = 190.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_HEAVY:
			start_hz = 310.0
			end_hz = 62.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_RAIL:
			start_hz = 2450.0
			end_hz = 260.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_SCATTER:
			start_hz = 640.0
			end_hz = 82.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_PULSE:
			start_hz = 1720.0
			end_hz = 340.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_REPEATER:
			start_hz = 2260.0
			end_hz = 510.0
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_LANCE:
			start_hz = 1380.0
			end_hz = 185.0
		var variant_pitch := 1.0 + (variant - 1) * 0.035
		var primary_hz := lerpf(start_hz, end_hz, pow(progress, 0.72)) * variant_pitch
		var secondary_hz: float = primary_hz * (1.48 + profile.modification_amount * 0.18)
		var sub_hz := lerpf(105.0 - tier * 8.0, 48.0, progress)
		primary_phase += TAU * primary_hz / mix_rate
		secondary_phase += TAU * secondary_hz / mix_rate
		sub_phase += TAU * sub_hz / mix_rate
		var attack := minf(progress / (0.025 if profile.family == WeaponSoundProfileScript.FAMILY_BEAM_LANCE else 0.012), 1.0)
		var envelope := attack * pow(1.0 - progress, 1.45 if profile.beam_weapon else 1.9)
		var transient := noise * exp(-progress * (23.0 if profile.family == WeaponSoundProfileScript.FAMILY_SCATTER else 34.0))
		var body: float = sin(primary_phase) * 0.62 + sin(secondary_phase) * (0.10 + profile.modification_amount * 0.08)
		if profile.family == WeaponSoundProfileScript.FAMILY_AUTOMATIC:
			body = sin(primary_phase) * 0.50 + transient * 0.44
		elif profile.family == WeaponSoundProfileScript.FAMILY_HEAVY:
			body = sin(primary_phase) * 0.48 + sin(sub_phase) * (0.34 + tier * 0.035) + transient * 0.32
		elif profile.family == WeaponSoundProfileScript.FAMILY_RAIL:
			body = sin(primary_phase) * 0.50 + sin(secondary_phase) * 0.21 + transient * 0.38
		elif profile.family == WeaponSoundProfileScript.FAMILY_SCATTER:
			body = sin(primary_phase) * 0.38 + sin(secondary_phase * 0.73) * 0.18 + transient * (0.40 + minf(profile.projectile_count, 6) * 0.025)
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_PULSE:
			body = sin(primary_phase) * 0.52 + sin(secondary_phase) * 0.23 + sin(primary_phase * 3.0) * 0.10
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_REPEATER:
			body = sin(primary_phase) * 0.45 + sin(secondary_phase) * 0.26 + transient * 0.18
		elif profile.family == WeaponSoundProfileScript.FAMILY_BEAM_LANCE:
			body = sin(primary_phase) * 0.44 + sin(secondary_phase) * 0.20 + sin(sub_phase) * (0.20 + tier * 0.035) + noise * exp(-progress * 9.0) * 0.10
		var modifier_layer := 0.0
		if profile.pierce_count > 0:
			modifier_layer += sin(TAU * (2650.0 + variant * 110.0) * float(index) / mix_rate) * exp(-progress * 16.0) * minf(profile.pierce_count, 2) * 0.065
		if profile.ricochet_count > 0:
			modifier_layer += sin(TAU * (690.0 + profile.ricochet_count * 55.0) * float(index) / mix_rate) * sqrt(progress) * (1.0 - progress) * 0.18
		if profile.knockback_ratio > 0.05:
			modifier_layer += sin(TAU * 54.0 * float(index) / mix_rate) * pow(1.0 - progress, 2.2) * minf(profile.knockback_ratio, 1.8) * 0.16
		var tier_body := sin(sub_phase) * float(tier) * 0.045 * pow(1.0 - progress, 1.35)
		var sample: float = body * envelope + transient * 0.18 + modifier_layer + tier_body
		samples[index] = sample
		peak = maxf(peak, absf(sample))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var gain := 24500.0 / peak
	for index in sample_count:
		bytes.encode_s16(index * 2, clampi(roundi(samples[index] * gain), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream




static func _synthesize_tone(start_hz: float, end_hz: float, duration: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := maxi(roundi(duration * mix_rate), 1)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var phase := 0.0
	for index in sample_count:
		var progress := float(index) / sample_count
		var frequency := lerpf(start_hz, end_hz, progress)
		phase += TAU * frequency / mix_rate
		var envelope := minf(progress / 0.08, 1.0) * pow(1.0 - progress, 1.8)
		bytes.encode_s16(index * 2, clampi(roundi(sin(phase) * envelope * 15000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream




static func _synthesize_afterburner() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.52
	var sample_count := roundi(duration * mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var primary_phase := 0.0
	var secondary_phase := 0.0
	var noise_state := 947_231
	var filtered_noise := 0.0
	for index in sample_count:
		var progress := float(index) / float(sample_count)
		var frequency := lerpf(74.0, 142.0, minf(progress / 0.42, 1.0))
		primary_phase += TAU * frequency / mix_rate
		secondary_phase += TAU * frequency * 2.03 / mix_rate
		noise_state = int(posmod(noise_state * 1103515245 + 12345, 2147483647))
		var noise := float(noise_state) / 1073741823.5 - 1.0
		filtered_noise = lerpf(filtered_noise, noise, 0.075)
		var attack := minf(progress / 0.028, 1.0)
		var release := pow(1.0 - progress, 0.72)
		var envelope := attack * release
		var ignition := noise * exp(-progress * 52.0) * 0.62
		var roar := sin(primary_phase) * 0.42 + sin(secondary_phase) * 0.16 + filtered_noise * 0.48
		var sample := (roar * envelope + ignition) * 0.72
		bytes.encode_s16(index * 2, clampi(roundi(sample * 26000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream




static func _synthesize_victory_theme() -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 4.0
	var sample_count := roundi(duration * mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var notes: Array[float] = [261.63, 329.63, 392.0, 523.25, 659.25, 783.99, 1046.5, 783.99]
	for index in sample_count:
		var time := float(index) / mix_rate
		var note_index := mini(floori(time / 0.5), notes.size() - 1)
		var note_time := fmod(time, 0.5)
		var envelope := minf(note_time / 0.035, 1.0) * minf((0.5 - note_time) / 0.12, 1.0)
		var sample := sin(TAU * notes[note_index] * time) * 0.68 + sin(TAU * notes[note_index] * 1.5 * time) * 0.2
		bytes.encode_s16(index * 2, clampi(roundi(sample * envelope * 11000.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = sample_count
	return stream




static func _synthesize_objective(ascending: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	var notes := [660.0, 880.0, 1320.0] if ascending else [880.0, 660.0, 330.0]
	for frequency in notes:
		bytes.append_array(_synthesize_tone(frequency, frequency, 0.12).data)
		var gap := PackedByteArray()
		gap.resize(882 * 2)
		bytes.append_array(gap)
	stream.data = bytes
	return stream
