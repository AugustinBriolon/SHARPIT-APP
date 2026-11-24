import Foundation

/// French gym words and what the catalog calls them. The catalog's names are the dataset's,
/// English for all but a few aliases, so a search typed in French is read through this list:
/// « pompes » finds « push up », « haltères incliné » finds « dumbbell incline ».
///
/// Keys and values are normalised as `ExerciseMediaCatalog.normalize` leaves them: lower case, no
/// accents. A key may be several words (« developpe couche »); a plural is looked up as written,
/// then without its final « s » or « x ».
nonisolated enum ExerciseFrenchGlossary {
    /// The longest French phrase the glossary holds, in words.
    private static let longestPhrase = 3

    /// The query as units to find, each with the spellings that satisfy it: the words typed and
    /// their English names. A name matches when it holds one spelling of every unit.
    static func alternatives(for normalizedQuery: String) -> [[String]] {
        let words = normalizedQuery.split(separator: " ").map(String.init)
        var units: [[String]] = []
        var index = 0
        while index < words.count {
            var matched = false
            for length in stride(from: min(longestPhrase, words.count - index), through: 1, by: -1) {
                let phrase = words[index..<index + length].joined(separator: " ")
                guard let english = english(for: phrase) else { continue }
                units.append([phrase] + english)
                index += length
                matched = true
                break
            }
            if !matched {
                units.append([words[index]])
                index += 1
            }
        }
        return units
    }

    private static func english(for phrase: String) -> [String]? {
        if let found = terms[phrase] { return found }
        guard let last = phrase.last, last == "s" || last == "x" else { return nil }
        return terms[String(phrase.dropLast())]
    }

    private static let terms: [String: [String]] = [
        // Movements
        "developpe couche": ["bench press"],
        "developpe incline": ["incline press", "incline bench press"],
        "developpe decline": ["decline press", "decline bench press"],
        "developpe militaire": ["military press", "overhead press"],
        "developpe epaule": ["shoulder press"],
        "developpe": ["press"],
        "presse": ["press", "sled"],
        "souleve de terre": ["deadlift"],
        "souleve": ["deadlift", "lift"],
        "pompe": ["push up"],
        "traction": ["pull up", "chin up"],
        "tirage vertical": ["pulldown"],
        "tirage horizontal": ["row"],
        "tirage menton": ["upright row"],
        "tirage": ["row", "pull", "pulldown"],
        "rowing": ["row"],
        "fente": ["lunge"],
        "flexion": ["curl", "flexion"],
        "extension": ["extension"],
        "elevation": ["raise"],
        "releve": ["raise"],
        "ecarte": ["fly"],
        "papillon": ["fly"],
        "oiseau": ["rear", "reverse fly"],
        "haussement": ["shrug"],
        "gainage": ["plank"],
        "planche": ["plank"],
        "pont": ["bridge"],
        "abdo": ["crunch", "sit up"],
        "abdominaux": ["crunch", "sit up"],
        "releve de jambe": ["leg raise"],
        "rotation": ["rotation", "twist"],
        "torsion": ["twist"],
        "saut": ["jump"],
        "saute": ["jump"],
        "corde a sauter": ["jump rope"],
        "marche": ["walk", "step"],
        "montee": ["step"],
        "grimpeur": ["mountain climber"],
        "course": ["run"],
        "etirement": ["stretch"],
        "poirier": ["handstand"],
        "equilibre": ["balance", "handstand"],
        "cercle": ["circle"],
        "balancement": ["swing"],
        "arrache": ["snatch"],
        "epaule jete": ["clean and jerk"],
        "epaule": ["shoulder"],
        "coup de pied": ["kick"],
        // Equipment
        "haltere": ["dumbbell"],
        "barre": ["barbell", "bar"],
        "barre ez": ["ez"],
        "poulie": ["cable"],
        "cable": ["cable"],
        "corde": ["rope"],
        "elastique": ["band"],
        "bande": ["band"],
        "banc": ["bench"],
        "ballon": ["ball"],
        "balle": ["ball"],
        "medecine ball": ["medicine ball"],
        "machine": ["machine", "lever"],
        "guidee": ["smith"],
        "cadre guide": ["smith"],
        "pupitre": ["preacher"],
        "anneau": ["ring"],
        "sangle": ["suspended", "suspension"],
        "serviette": ["towel"],
        "chaise": ["chair"],
        "mur": ["wall"],
        "sol": ["floor"],
        "velo": ["bike", "bicycle"],
        "roue": ["wheel", "roller"],
        "roulette": ["wheel", "roller"],
        "rouleau": ["roller"],
        "poids du corps": ["bodyweight", "body weight"],
        "leste": ["weighted"],
        "lestee": ["weighted"],
        "assiste": ["assisted"],
        // Body
        "bras": ["arm"],
        "avant bras": ["wrist", "forearm"],
        "poignet": ["wrist"],
        "coude": ["elbow"],
        "main": ["hand"],
        "doigt": ["finger"],
        "jambe": ["leg"],
        "cuisse": ["quad", "leg"],
        "quadriceps": ["quad"],
        "ischio": ["hamstring"],
        "ischios jambiers": ["hamstring"],
        "mollet": ["calf", "calves"],
        "cheville": ["ankle"],
        "talon": ["heel"],
        "orteil": ["toe"],
        "genou": ["knee"],
        "hanche": ["hip"],
        "bassin": ["pelvic", "hip"],
        "fessier": ["glute"],
        "fesse": ["glute"],
        "dos": ["back"],
        "lombaire": ["hyperextension", "back"],
        "trapeze": ["shrug"],
        "nuque": ["neck", "behind"],
        "cou": ["neck"],
        "tete": ["head", "overhead"],
        "menton": ["chin"],
        "poitrine": ["chest"],
        "pectoraux": ["chest", "pec"],
        "pec": ["chest", "pec"],
        "deltoide": ["delt"],
        "oblique": ["oblique"],
        "adducteur": ["adduction", "adductor"],
        "abducteur": ["abduction"],
        // Position and grip
        "assis": ["seated"],
        "assise": ["seated"],
        "debout": ["standing"],
        "allonge": ["lying"],
        "couche": ["lying"],
        "a genoux": ["kneeling"],
        "penche": ["bent"],
        "incline": ["incline"],
        "decline": ["decline"],
        "suspendu": ["hanging", "suspended"],
        "prise": ["grip"],
        "serre": ["close", "narrow"],
        "serree": ["close", "narrow"],
        "large": ["wide"],
        "marteau": ["hammer"],
        "neutre": ["neutral"],
        "inverse": ["reverse", "inverted"],
        "inversee": ["reverse", "inverted"],
        "alterne": ["alternate", "alternating"],
        "unilateral": ["single", "one"],
        "un bras": ["one arm", "single arm"],
        "une jambe": ["one leg", "single leg"],
        "deux": ["two", "double"],
        "lateral": ["lateral", "side"],
        "laterale": ["lateral", "side"],
        "frontal": ["front"],
        "frontale": ["front"],
        "avant": ["front", "forward"],
        "arriere": ["rear", "back", "reverse"],
        "dessus": ["overhead", "over"],
        "haut": ["high", "upper"],
        "bas": ["low", "lower"],
        "droit": ["straight"],
        "tendu": ["straight", "stiff"],
        "croise": ["cross"],
        "militaire": ["military"],
        "bulgare": ["split squat"],
        "roumain": ["romanian"],
        "sumo": ["sumo"],
    ]
}
