import Foundation

/// What the athlete has typed, and the patch it amounts to.
///
/// A struct rather than state scattered across a view: the interesting part of a profile
/// form is not its layout but which fields it will send, and that has to be provable without
/// a view. `patch(against:)` is the whole contract — it compares what was typed with what
/// was loaded and names only the difference.
nonisolated struct ProfileFormState: Equatable {
    // Profil.
    var heightCm = ""
    var birthDate: Date?
    var targetWeightKg = ""
    var sleepTargetHours = ""
    var sleepBedtime = ""

    // Seuils & repères.
    var ftpW = ""
    var maxHr = ""
    var lthr = ""
    var runThresholdPace = ""
    var swimCss = ""
    var poolLength = ""

    init() {}

    /// Fills the fields from a loaded profile, in the format each one is typed in.
    init(profile: V1AthleteProfile) {
        heightCm = ProfileFieldFormat.integer(profile.heightCm)
        birthDate = profile.birthDate
        targetWeightKg = ProfileFieldFormat.decimal(profile.targetWeightKg)
        sleepTargetHours = ProfileFieldFormat.hours(profile.sleepTargetMinutes)
        sleepBedtime = ProfileFieldFormat.clock(profile.sleepBedtimeTargetMin)
        ftpW = ProfileFieldFormat.integer(profile.ftpW)
        maxHr = ProfileFieldFormat.integer(profile.maxHr)
        lthr = ProfileFieldFormat.integer(profile.lthr)
        runThresholdPace = ProfileFieldFormat.pace(profile.runThresholdPaceSecPerKm)
        swimCss = ProfileFieldFormat.pace(profile.swimCssSecPer100m)
        poolLength = ProfileFieldFormat.integer(profile.defaultPoolLengthM)
    }

    /// The reason an entry cannot be saved, or nil when every field reads.
    ///
    /// A field the athlete emptied is valid — it clears the value. A field holding something
    /// that is not a number is not, and refusing the save is the only way to say so before
    /// the server does.
    var firstError: (field: ProfileFormField, message: String)? {
        for field in ProfileFormField.allCases {
            if let message = error(for: field) { return (field, message) }
        }
        return nil
    }

    func error(for field: ProfileFormField) -> String? {
        let text = self[field]
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        switch field {
        case .heightCm:
            return bounded(text, min: 100, max: 250, unit: "cm")
        case .targetWeightKg:
            guard let value = ProfileFieldFormat.parseDecimal(text) else { return "Un poids en kg." }
            return (30...250).contains(value) ? nil : "Entre 30 et 250 kg."
        case .sleepTargetHours:
            guard let value = ProfileFieldFormat.parseDecimal(text) else { return "Un nombre d'heures." }
            return (4...12).contains(value) ? nil : "Entre 4 et 12 heures."
        case .sleepBedtime:
            return ProfileFieldFormat.parseClock(text) == nil ? "Une heure, comme 22:30." : nil
        case .ftpW:
            return ProfileFieldFormat.parseInteger(text) == nil ? "Une puissance en watts." : nil
        case .maxHr, .lthr:
            return bounded(text, min: 80, max: 240, unit: "bpm")
        case .runThresholdPace:
            return ProfileFieldFormat.parsePace(text) == nil ? "Une allure, comme 4:15." : nil
        case .swimCss:
            return ProfileFieldFormat.parsePace(text) == nil ? "Une allure, comme 1:38." : nil
        case .poolLength:
            return bounded(text, min: 10, max: 100, unit: "m")
        }
    }

    /// Only what changed, so a form the athlete opened and closed sends nothing.
    func patch(against profile: V1AthleteProfile) -> AthleteProfilePatch {
        var patch = AthleteProfilePatch()
        patch.setIfChanged(.heightCm, int: ProfileFieldFormat.parseInteger(heightCm), was: profile.heightCm)
        patch.setIfChanged(
            .targetWeightKg,
            double: ProfileFieldFormat.parseDecimal(targetWeightKg),
            was: profile.targetWeightKg
        )
        patch.setIfChanged(
            .sleepTargetMinutes,
            int: ProfileFieldFormat.parseHours(sleepTargetHours),
            was: profile.sleepTargetMinutes
        )
        patch.setIfChanged(
            .sleepBedtimeTargetMin,
            int: ProfileFieldFormat.parseClock(sleepBedtime),
            was: profile.sleepBedtimeTargetMin
        )
        patch.setIfChanged(.ftpW, int: ProfileFieldFormat.parseInteger(ftpW), was: profile.ftpW)
        patch.setIfChanged(.maxHr, int: ProfileFieldFormat.parseInteger(maxHr), was: profile.maxHr)
        patch.setIfChanged(.lthr, int: ProfileFieldFormat.parseInteger(lthr), was: profile.lthr)
        patch.setIfChanged(
            .runThresholdPaceSecPerKm,
            double: ProfileFieldFormat.parsePace(runThresholdPace),
            was: profile.runThresholdPaceSecPerKm
        )
        patch.setIfChanged(
            .swimCssSecPer100m,
            double: ProfileFieldFormat.parsePace(swimCss),
            was: profile.swimCssSecPer100m
        )
        patch.setIfChanged(
            .defaultPoolLengthM,
            int: ProfileFieldFormat.parseInteger(poolLength),
            was: profile.defaultPoolLengthM
        )
        // A `@db.Date` compared by instant would resend the same day on every save.
        if !ProfileFieldFormat.isSameDay(birthDate, profile.birthDate) {
            patch.set(.birthDate, string: ProfileFieldFormat.isoDay(birthDate))
        }
        return patch
    }

    subscript(field: ProfileFormField) -> String {
        switch field {
        case .heightCm: heightCm
        case .targetWeightKg: targetWeightKg
        case .sleepTargetHours: sleepTargetHours
        case .sleepBedtime: sleepBedtime
        case .ftpW: ftpW
        case .maxHr: maxHr
        case .lthr: lthr
        case .runThresholdPace: runThresholdPace
        case .swimCss: swimCss
        case .poolLength: poolLength
        }
    }

    private func bounded(_ text: String, min: Int, max: Int, unit: String) -> String? {
        guard let value = ProfileFieldFormat.parseInteger(text) else { return "Un nombre en \(unit)." }
        return (min...max).contains(value) ? nil : "Entre \(min) et \(max) \(unit)."
    }
}

/// The typed fields, in reading order. `birthDate` is absent: a date picker cannot hold an
/// entry that does not parse.
nonisolated enum ProfileFormField: String, CaseIterable, Sendable {
    case heightCm
    case targetWeightKg
    case sleepTargetHours
    case sleepBedtime
    case ftpW
    case maxHr
    case lthr
    case runThresholdPace
    case swimCss
    case poolLength
}
