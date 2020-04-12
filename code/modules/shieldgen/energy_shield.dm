#define SHIELD_VISIBLE 1
#define SHIELD_BROKEN 2
#define SHIELD_INVISIBLE 3

//
// This is the shield effect object for the supercool shield gens.
//
/obj/effect/shield
	name = "energy shield"
	desc = "An impenetrable field of energy, capable of blocking anything as long as it's active."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "shield"
	anchored = 1
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	density = 1
	var/obj/machinery/power/shield_generator/gen = null // Owning generator
	var/disabled_for = 0
	var/diffused_for = 0
	can_atmos_pass = ATMOS_PASS_YES
	var/adjacent_fields = 0 // It's a bitfield

/obj/effect/shield/update_icon()
	if(gen && gen.check_flag(MODEFLAG_PHOTONIC) && !disabled_for && !diffused_for)
		set_opacity(1)
	else
		set_opacity(0)

	if(gen && gen.check_flag(MODEFLAG_OVERCHARGE))
		icon_state = "shield_overcharged"
	else
		icon_state = "shield_normal"

	if(density)
		set_light(3, 3, "#66FFFF")
	else
		set_light(0)


// Prevents singularities and pretty much everything else from moving the field segments away.
// The only thing that is allowed to move us is the Destroy() proc.
/obj/effect/shield/forceMove()
	if(QDELING(src))
		return ..()
	return 0

/obj/effect/shield/Destroy()
	if(can_atmos_pass != ATMOS_PASS_YES)
		update_nearby_tiles()
	. = ..()
	if(gen)
		if(src in gen.field_segments)
			gen.field_segments -= src
		if(src in gen.damaged_segments)
			gen.damaged_segments -= src
		gen = null

// Temporarily collapses this shield segment.
/obj/effect/shield/proc/fail(var/duration)
	if(duration <= 0)
		return

	if(gen)
		gen.damaged_segments |= src
	disabled_for += duration
	set_density(0)
	set_invisibility(INVISIBILITY_MAXIMUM)
	update_nearby_tiles()
	update_icon()
	update_explosion_resistance()


// Regenerates this shield segment.
/obj/effect/shield/proc/regenerate()
	if(!gen)
		return

	disabled_for = max(0, disabled_for - 1)
	diffused_for = max(0, diffused_for - 1)

	if(!disabled_for && !diffused_for)
		set_density(1)
		set_invisibility(0)
		update_nearby_tiles()
		update_icon()
		update_explosion_resistance()
		gen.damaged_segments -= src


/obj/effect/shield/proc/diffuse(var/duration)
	// The shield is trying to counter diffusers. Cause lasting stress on the shield.
	if(gen.check_flag(MODEFLAG_BYPASS) && !disabled_for)
		take_damage(duration * rand(8, 12), SHIELD_DAMTYPE_EM)
		return

	diffused_for = max(duration, 0)
	gen.damaged_segments |= src
	set_density(0)
	set_invisibility(INVISIBILITY_MAXIMUM)
	update_nearby_tiles()
	update_icon()
	update_explosion_resistance()

/obj/effect/shield/attack_generic(var/source, var/damage, var/emote)
	take_damage(damage, SHIELD_DAMTYPE_PHYSICAL)
	if(gen.check_flag(MODEFLAG_OVERCHARGE) && istype(source, /mob/living/))
		overcharge_shock(source)
	..(source, damage, emote)


/obj/effect/shield/proc/update_connections(var/obj/effect/shield/friend)
	if(adjacent_fields)
		return

	var/list/friends = list()
	for(var/direction in cardinal)
		var/turf/T = get_step(src, direction)
		var/obj/effect/shield/S = locate() in T
		if(S?.gen == gen) //No shield blending!!!
			adjacent_fields |= direction
			friends |= S

	if(!friend)
		
/*
	//Wow we're lame
	if(!adjacent_fields)
		adjacent_fields = -1
		icon_state = "shield_corner_base"
		return

	//Multiple bits means a middle section or corner
	if((adjacent_fields & (adjacent_fields - 1)) != 0)
		switch(adjacent_fields)
			if(NORTH|SOUTH) //Middle vertical section
				if(x < gen.x) //Left of generator goes north
					dir = NORTH
				else
					dir = SOUTH
			if(EAST|WEST) //Middle horizontal section
				if(y < gen.y) //South of generator goes left
					dir = WEST
				else
					dir = EAST
			else //Corner
				icon_state = "shield_corner"
				dir = adjacent_fields

				var/image/start = image(icon, icon_state = "shield_start", dir = )
				var/image/end = image(icon, icon_state = "shield_end", dir = )
	else //Oh, ah, single bit set! Help us!
		dir = friend.dir

		if(friend.dir == get_dir(friend, src)) //They are facing us, we're an end!
			icon_state = "shield_end"
		else
			icon_state = "shield_start"
*/
	for(var/obj/effect/shield/S in friends)
		S.update_connections(src)
	
// Fails shield segments in specific range. Range of 1 affects the shielded turf only.
/obj/effect/shield/proc/fail_adjacent_segments(var/range, var/hitby = null)
	if(hitby)
		visible_message("<span class='danger'>\The [src] flashes a bit as \the [hitby] collides with it, eventually fading out in a rain of sparks!</span>")
	else
		visible_message("<span class='danger'>\The [src] flashes a bit as it eventually fades out in a rain of sparks!</span>")
	fail(range * 2)

	for(var/obj/effect/shield/S in range(range, src))
		// Don't affect shields owned by other shield generators
		if(S.gen != src.gen)
			continue
		// The closer we are to impact site, the longer it takes for shield to come back up.
		S.fail(-(-range + get_dist(src, S)) * 2)

// Small visual effect, makes the shield tiles brighten up by becoming more opaque for a moment, and spreads to nearby shields.
/obj/effect/shield/proc/flash_adjacent_segments(var/range)
	range = between(1, range, 10) // Sanity check
	for(var/obj/effect/shield/S in range(range, src))
		// Don't affect shields owned by other shield generators
		if(S.gen != src.gen || S == src)
			continue
		// Note: Range is a non-exact aproximation of the spread effect. If it doesn't look good
		// we'll need to switch to actually walking along the shields to get exact number of steps away.
		addtimer(CALLBACK(S, .proc/impact_flash), get_dist(src, S) * 2)
	impact_flash()

// Small visual effect, makes the shield tiles brighten up by becoming more opaque for a moment
/obj/effect/shield/proc/impact_flash()
	alpha = 100
	animate(src, alpha = initial(alpha), time = 1 SECOND)

// Just for fun
/obj/effect/shield/attack_hand(var/user)
	flash_adjacent_segments(3)

/obj/effect/shield/take_damage(var/damage, var/damtype, var/hitby)
	if(!gen)
		qdel(src)
		return

	if(!damtype)
		crash_with("CANARY: shield.take_damage() callled without damtype.")

	if(!damage)
		return

	damage = round(damage)

	new /obj/effect/temp_visual/shield_impact_effect(get_turf(src))

	switch(gen.deal_shield_damage(damage, damtype))
		if(SHIELD_ABSORBED)
			flash_adjacent_segments(round(damage/10)) // Nice visual effect only.
			return
		if(SHIELD_BREACHED_MINOR)
			fail_adjacent_segments(rand(1, 3), hitby)
			return
		if(SHIELD_BREACHED_MAJOR)
			fail_adjacent_segments(rand(2, 5), hitby)
			return
		if(SHIELD_BREACHED_CRITICAL)
			fail_adjacent_segments(rand(4, 8), hitby)
			return
		if(SHIELD_BREACHED_FAILURE)
			fail_adjacent_segments(rand(8, 16), hitby)
			return


// As we have various shield modes, this handles whether specific things can pass or not.
/obj/effect/shield/CanPass(var/atom/movable/mover, var/turf/target)
	// Somehow we don't have a generator. This shouldn't happen. Delete the shield.
	if(!gen)
		qdel(src)
		return 1

	if(disabled_for || diffused_for)
		return 1

	if(mover)
		return mover.can_pass_shield(gen)
	return 1

/obj/effect/shield/proc/set_can_atmos_pass(var/new_value)
	if(new_value == can_atmos_pass)
		return
	can_atmos_pass = new_value
	update_nearby_tiles()


// EMP. It may seem weak but keep in mind that multiple shield segments are likely to be affected.
/obj/effect/shield/emp_act(var/severity)
	if(!disabled_for)
		take_damage(rand(30,60) / severity, SHIELD_DAMTYPE_EM)


// Explosions
/obj/effect/shield/ex_act(var/severity)
	if(!disabled_for)
		take_damage(rand(10,15) / severity, SHIELD_DAMTYPE_PHYSICAL)


// Fire
/obj/effect/shield/fire_act(datum/gas_mixture/air, exposed_temperature, exposed_volume)
	if(!disabled_for)
		take_damage(rand(5,10), SHIELD_DAMTYPE_HEAT)


// Projectiles
/obj/effect/shield/bullet_act(var/obj/item/projectile/proj)
	if(proj.damage_type == BURN)
		take_damage(proj.get_structure_damage(), SHIELD_DAMTYPE_HEAT)
	else if (proj.damage_type == BRUTE)
		take_damage(proj.get_structure_damage(), SHIELD_DAMTYPE_PHYSICAL)
	else
		take_damage(proj.get_structure_damage(), SHIELD_DAMTYPE_EM)


// Attacks with hand tools. Blocked by Hyperkinetic flag.
/obj/effect/shield/attackby(var/obj/item/weapon/I as obj, var/mob/user as mob)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	user.do_attack_animation(src)

	if(gen.check_flag(MODEFLAG_HYPERKINETIC))
		user.visible_message("<span class='danger'>\The [user] hits \the [src] with \the [I]!</span>")
		if(I.damtype == BURN)
			take_damage(I.force, SHIELD_DAMTYPE_HEAT)
		else if (I.damtype == BRUTE)
			take_damage(I.force, SHIELD_DAMTYPE_PHYSICAL)
		else
			take_damage(I.force, SHIELD_DAMTYPE_EM)
	else
		user.visible_message("<span class='danger'>\The [user] tries to attack \the [src] with \the [I], but it passes through!</span>")


// Special treatment for meteors because they would otherwise penetrate right through the shield.
/obj/effect/shield/Bumped(var/atom/movable/mover)
	if(!gen)
		qdel(src)
		return 0
	mover.shield_impact(src)
	return ..()

// Meteors call this instad of Bumped for some reason
/obj/effect/shield/handle_meteor_impact(var/obj/effect/meteor/meteor)
	meteor.shield_impact(src)
	return !QDELETED(meteor) // If it was stopped it will have been deleted

/obj/effect/shield/proc/overcharge_shock(var/mob/living/M)
	M.adjustFireLoss(rand(20, 40))
	M.Weaken(5)
	to_chat(M, "<span class='danger'>As you come into contact with \the [src] a surge of energy paralyses you!</span>")
	take_damage(10, SHIELD_DAMTYPE_EM)

// Called when a flag is toggled. Can be used to add on-toggle behavior, such as visual changes.
/obj/effect/shield/proc/flags_updated()
	if(!gen)
		qdel(src)
		return

	// Update airflow - If atmospheric we block air as long as we're enabled (density works for this)
	set_can_atmos_pass(gen.check_flag(MODEFLAG_ATMOSPHERIC) ? ATMOS_PASS_DENSITY : ATMOS_PASS_YES)
	update_icon()
	update_explosion_resistance()

/obj/effect/shield/proc/update_explosion_resistance()
	if(gen && gen.check_flag(MODEFLAG_HYPERKINETIC))
		explosion_resistance = INFINITY
	else
		explosion_resistance = 0

//
// Visual effect of shield taking impact
//
/obj/effect/temp_visual/shield_impact_effect
	name = "shield impact"
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "shield_impact"
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	duration = 2 SECONDS
	randomdir = FALSE

//
// Shield collision checks below
//

// Called only if shield is active/not destroyed etc.
/atom/movable/proc/can_pass_shield(var/obj/machinery/power/shield_generator/gen)
	return 1


// Other mobs
/mob/living/can_pass_shield(var/obj/machinery/power/shield_generator/gen)
	return !gen.check_flag(MODEFLAG_NONHUMANS)

// Human mobs
/mob/living/carbon/human/can_pass_shield(var/obj/machinery/power/shield_generator/gen)
	if(isSynthetic())
		return !gen.check_flag(MODEFLAG_ANORGANIC)
	return !gen.check_flag(MODEFLAG_HUMANOIDS)

// Silicon mobs
/mob/living/silicon/can_pass_shield(var/obj/machinery/power/shield_generator/gen)
	return !gen.check_flag(MODEFLAG_ANORGANIC)


// Generic objects. Also applies to bullets and meteors.
/obj/can_pass_shield(var/obj/machinery/power/shield_generator/gen)
	return !gen.check_flag(MODEFLAG_HYPERKINETIC)

// Beams
/obj/item/projectile/beam/can_pass_shield(var/obj/machinery/power/shield_generator/gen)
	return !gen.check_flag(MODEFLAG_PHOTONIC)


// Shield on-impact logic here. This is called only if the object is actually blocked by the field (can_pass_shield applies first)
/atom/movable/proc/shield_impact(var/obj/effect/shield/S)
	return

/mob/living/shield_impact(var/obj/effect/shield/S)
	if(!S.gen.check_flag(MODEFLAG_OVERCHARGE))
		return
	S.overcharge_shock(src)

/obj/effect/meteor/shield_impact(var/obj/effect/shield/S)
	if(!S.gen.check_flag(MODEFLAG_HYPERKINETIC))
		return
	S.take_damage(get_shield_damage(), SHIELD_DAMTYPE_PHYSICAL, src)
	visible_message("<span class='danger'>\The [src] breaks into dust!</span>")
	make_debris()
	qdel(src)

#undef SHIELD_VISIBLE
#undef SHIELD_BROKEN
#undef SHIELD_INVISIBLE