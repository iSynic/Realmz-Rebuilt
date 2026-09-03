class_name PartySetupRules
extends RefCounted


static func difficulty_multiplier(difficulty: int) -> float:
	return 1.0 + float(clampi(difficulty, -2, 2)) * 0.33


static func experience_multiplier(recommended_levels: int, current_levels: int, difficulty: int) -> float:
	if recommended_levels <= 0 or current_levels <= 0:
		return 0.0
	return clampf(difficulty_multiplier(difficulty) * float(recommended_levels) / float(current_levels), 0.20, 2.50)


static func experience_percent(recommended_levels: int, current_levels: int, difficulty: int) -> int:
	return int(experience_multiplier(recommended_levels, current_levels, difficulty) * 100.0)


static func scale_experience(value: int, recommended_levels: int, current_levels: int, difficulty: int) -> int:
	return maxi(0, int(float(value) * experience_multiplier(recommended_levels, current_levels, difficulty)))


static func scale_experience_by_multiplier(value: int, multiplier: float) -> int:
	return maxi(0, int(float(value) * clampf(multiplier, 0.20, 2.50)))


static func scale_money(value: int, difficulty: int) -> int:
	return maxi(0, int(float(value) * difficulty_multiplier(difficulty)))
