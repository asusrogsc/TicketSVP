class_name People
## Génération des passagers : identité, titre de transport, vérité (valide / fraude), répliques.

const PRENOMS := ["Lucas", "Emma", "Nathan", "Léa", "Hugo", "Chloé", "Louis", "Manon", "Jules", "Camille",
	"Théo", "Sarah", "Noah", "Inès", "Gabriel", "Jade", "Arthur", "Zoé", "Mohamed", "Lina", "Kevin",
	"Océane", "Yanis", "Clara", "Mathis", "Ambre", "Enzo", "Lou", "Rayan", "Alice"]
const NOMS := ["Martin", "Bernard", "Dubois", "Thomas", "Robert", "Richard", "Petit", "Durand", "Leroy",
	"Moreau", "Simon", "Laurent", "Lefebvre", "Michel", "Garcia", "David", "Bertrand", "Roux", "Vincent",
	"Fournier", "Peeters", "Janssens", "Maes", "Claes", "Mertens"]

const SALUT := ["Bonjour !", "Oui oui, voilà.", "Tenez.", "Ah, un contrôle...", "Bonjour monsieur.",
	"Pas de souci.", "C'est pour quoi ?", "Je l'ai quelque part...", "Encore ?!"]
const OK := ["Merci, bonne journée !", "Bonne journée.", "Merci.", "À la prochaine !"]
const FRAUDE_NONE := ["Euh... je l'ai oublié à la maison.", "J'allais en acheter un, promis !",
	"C'est mon pote qui l'a.", "Ah... la machine était en panne."]
const RALE := ["Sérieux ?! Pour une fois...", "C'est abusé !", "Vous avez rien de mieux à faire ?",
	"Pff... Bon, d'accord.", "Je vais faire une réclamation !"]
const INJUSTE := ["Mais il est valide mon ticket !", "Vous savez lire ?!", "J'appelle mon avocat !",
	"C'est une erreur, regardez la date !"]

const COULEURS := [Color(0.8, 0.2, 0.2), Color(0.2, 0.4, 0.8), Color(0.25, 0.6, 0.3), Color(0.9, 0.7, 0.2),
	Color(0.5, 0.3, 0.6), Color(0.15, 0.15, 0.18), Color(0.9, 0.9, 0.88), Color(0.55, 0.35, 0.2),
	Color(0.95, 0.5, 0.2), Color(0.3, 0.7, 0.75)]
const PEAUX := [Color(0.98, 0.84, 0.72), Color(0.9, 0.72, 0.56), Color(0.72, 0.52, 0.36), Color(0.5, 0.34, 0.24),
	Color(0.36, 0.24, 0.17)]
const CHEVEUX := [Color(0.1, 0.08, 0.06), Color(0.35, 0.2, 0.1), Color(0.75, 0.55, 0.25), Color(0.6, 0.6, 0.6),
	Color(0.55, 0.15, 0.1), Color(0.95, 0.85, 0.55)]


static func _date_offset(days: int) -> Dictionary:
	var t := Time.get_unix_time_from_datetime_dict({"year": Game.today.y, "month": Game.today.m, "day": Game.today.d})
	var d := Time.get_datetime_dict_from_unix_time(t + days * 86400)
	return {"d": d.day, "m": d.month, "y": d.year}


## Passager ordinaire tiré au hasard pour la ligne `line`.
static func random_passenger(line: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var p := {
		"id": "", "special": false,
		"name": "%s %s" % [PRENOMS[rng.randi() % PRENOMS.size()], NOMS[rng.randi() % NOMS.size()]],
		"body": COULEURS[rng.randi() % COULEURS.size()], "legs": COULEURS[rng.randi() % COULEURS.size()].darkened(0.4),
		"skin": PEAUX[rng.randi() % PEAUX.size()], "hair": CHEVEUX[rng.randi() % CHEVEUX.size()],
		"greet": SALUT[rng.randi() % SALUT.size()],
	}
	var r := rng.randf()
	var other_line := 2 if line.id == 1 else 1
	if r < 0.62:
		if rng.randf() < 0.5:
			p.ticket = {"kind": "Ticket 1 trajet", "line": line.id, "valide": true,
				"detail": "Composté à %02d:%02d" % [7 + rng.randi() % 3, rng.randi() % 60]}
		else:
			p.ticket = {"kind": "Abonnement mensuel", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(rng.randi_range(1, 25)))}
		p.truth = "valide"
	elif r < 0.73:
		p.ticket = {"kind": "Aucun titre", "line": -1, "valide": false, "detail": ""}
		p.greet = FRAUDE_NONE[rng.randi() % FRAUDE_NONE.size()]
		p.truth = "fraude"; p.reason = "pas de titre de transport"
	elif r < 0.84:
		p.ticket = {"kind": "Abonnement mensuel", "line": 0, "valide": false,
			"detail": "Valable jusqu'au " + Game.date_str(_date_offset(-rng.randi_range(1, 40)))}
		p.truth = "fraude"; p.reason = "abonnement expiré"
	elif r < 0.93:
		p.ticket = {"kind": "Ticket 1 trajet", "line": other_line, "valide": false,
			"detail": "Composté à %02d:%02d" % [7 + rng.randi() % 3, rng.randi() % 60]}
		p.truth = "fraude"; p.reason = "ticket d'une autre ligne"
	else:
		p.ticket = {"kind": "Ticket 1 trajet", "line": line.id, "valide": false, "detail": "NON COMPOSTÉ"}
		p.truth = "fraude"; p.reason = "ticket non composté"
	p.ok = OK[rng.randi() % OK.size()]
	p.fine_reaction = RALE[rng.randi() % RALE.size()] if p.truth == "fraude" else INJUSTE[rng.randi() % INJUSTE.size()]
	return p


## Personnages spéciaux (rares). `model` : nom d'un fichier res://models/<model>.glb facultatif.
static func specials(line: Dictionary) -> Array:
	return [
		{
			"id": "mzelle", "special": true, "name": "Mzelle", "model": "Mzelle", "model_height": 1.52,
			"body": Color(0.12, 0.12, 0.14), "legs": Color(0.95, 0.95, 0.95), "skin": Color(0.99, 0.88, 0.8),
			"hair": Color(0.97, 0.9, 0.7), "twintails": true, "small": true,
			"can_be_kissed": true,
			"greet": "Un contrôle ? Hihi, tiens, mon pass étudiant ! ♪",
			"ticket": {"kind": "Pass étudiant", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(60))},
			"truth": "valide", "ok": "Merci monsieur le contrôleur ! Tu veux un bonbon ? ♪",
			"fine_reaction": "Quoi ?! Mais il est valide... Tu es méchant ! (elle boude)",
		},
		{
			"id": "mzelle", "special": true, "name": "Mzelle", "model": "Mzelle", "model_height": 1.52,
			"body": Color(0.12, 0.12, 0.14), "legs": Color(0.95, 0.95, 0.95), "skin": Color(0.99, 0.88, 0.8),
			"hair": Color(0.97, 0.9, 0.7), "twintails": true, "small": true,
			"can_be_kissed": true,
			"greet": "Un contrôle ? Hihi, tiens, mon pass étudiant ! ♪",
			"ticket": {"kind": "Pass étudiant", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(60))},
			"truth": "valide", "ok": "Merci monsieur le contrôleur ! Tu veux un bonbon ? ♪",
			"fine_reaction": "Quoi ?! Mais il est valide... Tu es méchant ! (elle boude)",
		},
		{
			"id": "mzelle", "special": true, "name": "Mzelle", "model": "Mzelle", "model_height": 1.52,
			"body": Color(0.12, 0.12, 0.14), "legs": Color(0.95, 0.95, 0.95), "skin": Color(0.99, 0.88, 0.8),
			"hair": Color(0.97, 0.9, 0.7), "twintails": true, "small": true,
			"can_be_kissed": true,
			"greet": "Un contrôle ? Hihi, tiens, mon pass étudiant ! ♪",
			"ticket": {"kind": "Pass étudiant", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(60))},
			"truth": "valide", "ok": "Merci monsieur le contrôleur ! Tu veux un bonbon ? ♪",
			"fine_reaction": "Quoi ?! Mais il est valide... Tu es méchant ! (elle boude)",
		},
		{
			"id": "mzelle", "special": true, "name": "Mzelle", "model": "Mzelle", "model_height": 1.52,
			"body": Color(0.12, 0.12, 0.14), "legs": Color(0.95, 0.95, 0.95), "skin": Color(0.99, 0.88, 0.8),
			"hair": Color(0.97, 0.9, 0.7), "twintails": true, "small": true,
			"can_be_kissed": true,
			"greet": "Un contrôle ? Hihi, tiens, mon pass étudiant ! ♪",
			"ticket": {"kind": "Pass étudiant", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(60))},
			"truth": "valide", "ok": "Merci monsieur le contrôleur ! Tu veux un bonbon ? ♪",
			"fine_reaction": "Quoi ?! Mais il est valide... Tu es méchant ! (elle boude)",
		},
		{
			"id": "pampa", "special": true, "name": "Le Pampa", "model": "pampa",
			"body": Color(0.35, 0.65, 0.25), "legs": Color(0.3, 0.55, 0.2), "skin": Color(0.4, 0.7, 0.3),
			"hair": Color(0.4, 0.7, 0.3), "cactus": true,
			"greet": "...........!",
			"ticket": {"kind": "Aucun titre", "line": -1, "valide": false, "detail": ""},
			"truth": "fraude", "reason": "les cactus aussi paient leur ticket",
			"ok": "...♪ (le Pampa repart en courant les bras levés)",
			"fine_reaction": "1000 AIGUILLES ! (tu as mal partout, mais l'amende est encaissée)",
		},
		{
			"id": "mamie", "special": true, "name": "Mamie Ginette", "model": "mamie",
			"body": Color(0.6, 0.45, 0.6), "legs": Color(0.3, 0.25, 0.3), "skin": Color(0.95, 0.82, 0.74),
			"hair": Color(0.85, 0.85, 0.88),
			"greet": "Oh mon petit, ma carte senior... Elle est encore bonne, non ?",
			"ticket": {"kind": "Abonnement Senior", "line": 0, "valide": false,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(-1))},
			"truth": "fraude", "reason": "carte senior expirée d'hier",
			"ok": "Merci mon petit, tu es bien gentil.",
			"fine_reaction": "Oh... à mon âge... Bon, je la renouvelle demain. Tu as raison.",
		},
		{
			"id": "touriste", "special": true, "name": "John (touriste)", "model": "touriste",
			"body": Color(0.95, 0.55, 0.65), "legs": Color(0.85, 0.75, 0.55), "skin": Color(0.98, 0.78, 0.68),
			"hair": Color(0.9, 0.75, 0.4),
			"greet": "Hello! Is this the bus to the... euh... Université ? Here, my ticket!",
			"ticket": {"kind": "Pass touristique 3 jours", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(2))},
			"truth": "valide", "ok": "Thank you! Merci beaucoup!",
			"fine_reaction": "What?! But it's a valid pass! This country is crazy!",
		},
		{
			"id": "julie", "special": true, "name": "Julie", "model": "julie", "model_height": 1.67,
			"body": Color(0.95, 0.95, 0.93), "legs": Color(0.1, 0.1, 0.11), "skin": Color(0.98, 0.84, 0.74),
			"hair": Color(0.08, 0.06, 0.06), "long_hair": true, "gloves": true,
			"can_be_kissed": true,
			"greet": "Salut ! Je rentre au 7th Heaven. Voilà mon abonnement.",
			"ticket": {"kind": "Abonnement mensuel", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(12))},
			"truth": "valide", "ok": "Merci ! Passe au bar un de ces soirs, la première est offerte.",
			"fine_reaction": "Une amende ?! (elle fait craquer ses poings) ...Relis bien la date.",
		},
		{
			"id": "judith", "special": true, "name": "Judith", "model": "judith",
			"body": Color(0.95, 0.92, 0.8), "legs": Color(0.55, 0.4, 0.25), "skin": Color(0.99, 0.86, 0.77),
			"hair": Color(0.1, 0.07, 0.06), "long_hair": true, "hat": true, "scale": 0.7,
			"can_be_kissed": true,
			"greet": "Bonjour monsieur ! J'ai mon ticket enfant, c'est maman qui l'a acheté !",
			# Petite Tifa
			"ticket": {"kind": "Ticket Enfant (-12 ans)", "line": line.get("id", 0), "valide": true,
				"detail": "Composté à %02d:%02d" % [8, 15]},
			"truth": "valide", "ok": "Merci ! Je vais voir le puits de Nibelheim avec mes copains !",
			"fine_reaction": "(elle se met à pleurer) Mais... c'est maman qui l'a acheté...",
		},
		{
			"id": "fany", "special": true, "name": "Fany", "model": "fany",
			"body": Color(0.25, 0.35, 0.75), "legs": Color(0.25, 0.35, 0.75), "skin": Color(0.98, 0.84, 0.74),
			"hair": Color(0.08, 0.06, 0.06), "braid": true,
			"can_be_kissed": true,
			"greet": "Je vais à Wall Market, chez Don Corneo... C'est bien cette ligne ?",
			# Tifa (robe chinoise)
			"ticket": {"kind": "Ticket 1 trajet", "line": 2 if line.get("id", 0) == 1 else 1, "valide": false,
				"detail": "Composté à %02d:%02d" % [21, 30]},
			"truth": "fraude", "reason": "ticket de la Ligne 2 (Wall Market, c'est pas ici !)",
			"ok": "Super, merci ! (tu viens de laisser passer un ticket d'une autre ligne...)",
			"fine_reaction": "Oh non... j'ai pris la mauvaise ligne ? Bon... je paie. Mais Don Corneo va m'attendre !",
		},
		{
			"id": "agent", "special": true, "name": "Agent Azimov", "model": "agent",
			"body": Color(0.08, 0.08, 0.1), "legs": Color(0.08, 0.08, 0.1), "skin": Color(0.85, 0.68, 0.55),
			"hair": Color(0.05, 0.05, 0.05), "sunglasses": true,
			"greet": "Bonjour. Simple voyageur. Rien à signaler.",
			"ticket": {"kind": "Carte de service", "line": 0, "valide": true, "detail": "Contrôle qualité — Réseau Azimov"},
			"truth": "valide", "ok": "Excellent travail. Je le noterai dans mon rapport.",
			"fine_reaction": "Vous venez de mettre une amende à votre inspecteur. Ce sera dans mon rapport...",
		},
		{
			"id": "oldman", "special": true, "name": "Pépé Raymond", "model": "Oldman",
			"model_height": 1.7,
			"body": Color(0.45, 0.4, 0.38), "legs": Color(0.25, 0.25, 0.28),
			"skin": Color(0.9, 0.78, 0.7), "hair": Color(0.75, 0.75, 0.78),
			"role": "kiss_oldman",
			"greet": "Hein ? Contrôle ? J’ai ma carte senior… quelque part.",
			"ticket": {"kind": "Abonnement Senior", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(15))},
			"truth": "valide",
			"ok": "Merci mon garçon.",
			"fine_reaction": "Une amende ? À mon âge ? Vous n’avez pas honte ?",
		},
		{
			"id": "oldman", "special": true, "name": "Pépé Raymond", "model": "Oldman",
			"model_height": 1.7,
			"body": Color(0.45, 0.4, 0.38), "legs": Color(0.25, 0.25, 0.28),
			"skin": Color(0.9, 0.78, 0.7), "hair": Color(0.75, 0.75, 0.78),
			"role": "kiss_oldman",
			"greet": "Hein ? Contrôle ? J’ai ma carte senior… quelque part.",
			"ticket": {"kind": "Abonnement Senior", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(15))},
			"truth": "valide",
			"ok": "Merci mon garçon.",
			"fine_reaction": "Une amende ? À mon âge ? Vous n’avez pas honte ?",
		},
		{
			"id": "oldman", "special": true, "name": "Pépé Raymond", "model": "Oldman",
			"model_height": 1.7,
			"body": Color(0.45, 0.4, 0.38), "legs": Color(0.25, 0.25, 0.28),
			"skin": Color(0.9, 0.78, 0.7), "hair": Color(0.75, 0.75, 0.78),
			"role": "kiss_oldman",
			"greet": "Hein ? Contrôle ? J’ai ma carte senior… quelque part.",
			"ticket": {"kind": "Abonnement Senior", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(15))},
			"truth": "valide",
			"ok": "Merci mon garçon.",
			"fine_reaction": "Une amende ? À mon âge ? Vous n’avez pas honte ?",
		},
		{
			"id": "oldman", "special": true, "name": "Pépé Raymond", "model": "Oldman",
			"model_height": 1.7,
			"body": Color(0.45, 0.4, 0.38), "legs": Color(0.25, 0.25, 0.28),
			"skin": Color(0.9, 0.78, 0.7), "hair": Color(0.75, 0.75, 0.78),
			"role": "kiss_oldman",
			"greet": "Hein ? Contrôle ? J’ai ma carte senior… quelque part.",
			"ticket": {"kind": "Abonnement Senior", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(15))},
			"truth": "valide",
			"ok": "Merci mon garçon.",
			"fine_reaction": "Une amende ? À mon âge ? Vous n’avez pas honte ?",
		},
		{
			"id": "oldman", "special": true, "name": "Pépé Raymond", "model": "Oldman",
			"model_height": 1.7,
			"body": Color(0.45, 0.4, 0.38), "legs": Color(0.25, 0.25, 0.28),
			"skin": Color(0.9, 0.78, 0.7), "hair": Color(0.75, 0.75, 0.78),
			"role": "kiss_oldman",
			"greet": "Hein ? Contrôle ? J’ai ma carte senior… quelque part.",
			"ticket": {"kind": "Abonnement Senior", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(15))},
			"truth": "valide",
			"ok": "Merci mon garçon.",
			"fine_reaction": "Une amende ? À mon âge ? Vous n’avez pas honte ?",
		},
		{
			"id": "male1", "special": true, "name": "Roshi", "model": "male1",
			"model_height": 1.7,
			"body": Color(0.45, 0.4, 0.38), "legs": Color(0.25, 0.25, 0.28),
			"skin": Color(0.9, 0.78, 0.7), "hair": Color(0.75, 0.75, 0.78),
			"role": "kiss_oldman",
			"greet": "Hein ? Contrôle ? J’ai ma carte senior… quelque part.",
			"ticket": {"kind": "Abonnement Senior", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(15))},
			"truth": "valide",
			"ok": "Merci mon garçon.",
			"fine_reaction": "Une amende ? À mon âge ? Vous n’avez pas honte ?",
		},
		{
			"id": "male2", "special": true, "name": "Alex", "model": "male2",
			"model_height": 1.7,
			"body": Color(0.45, 0.4, 0.38), "legs": Color(0.25, 0.25, 0.28),
			"skin": Color(0.9, 0.78, 0.7), "hair": Color(0.75, 0.75, 0.78),
			"role": "kiss_oldman",
			"greet": "Hein ? Contrôle ? J’ai ma carte senior… quelque part.",
			"ticket": {"kind": "Abonnement Senior", "line": 0, "valide": true,
				"detail": "Valable jusqu'au " + Game.date_str(_date_offset(15))},
			"truth": "valide",
			"ok": "Merci mon garçon.",
			"fine_reaction": "Une amende ? À mon âge ? Vous n’avez pas honte ?",
		},
	]
