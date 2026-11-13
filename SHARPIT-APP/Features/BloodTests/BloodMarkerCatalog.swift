import Foundation

/// One analyte SHARPIT keeps from a lab report. Keys, units and plausible ranges mirror the web's
/// `@sharpit/app/lib/blood-markers/catalog` (SHARPIT ADR-128), which refuses anything else. The
/// aliases are this app's own: the labels labs print, already folded by `BloodReportText.folded`.
nonisolated struct BloodMarker: Equatable, Sendable {
    let key: String
    let label: String
    let unit: String
    /// The widest values a living adult can show — a misread guard, not a reference range.
    let plausible: ClosedRange<Double>
    let aliases: [String]
}

nonisolated enum BloodMarkerCatalog {
    static let all: [BloodMarker] = [
        BloodMarker(key: "red_blood_cells", label: "Hématies", unit: "T/L", plausible: 1...9,
                    aliases: ["hematies", "globules rouges", "erythrocytes"]),
        BloodMarker(key: "hemoglobin", label: "Hémoglobine", unit: "g/dL", plausible: 3...25,
                    aliases: ["hemoglobine"]),
        BloodMarker(key: "hematocrit", label: "Hématocrite", unit: "%", plausible: 10...75,
                    aliases: ["hematocrite"]),
        BloodMarker(key: "mcv", label: "V.G.M.", unit: "fL", plausible: 50...150,
                    aliases: ["v.g.m.", "vgm"]),
        BloodMarker(key: "mch", label: "T.C.M.H.", unit: "pg", plausible: 10...50,
                    aliases: ["t.c.m.h.", "tcmh"]),
        BloodMarker(key: "mchc", label: "C.C.M.H.", unit: "g/dL", plausible: 20...45,
                    aliases: ["c.c.m.h.", "ccmh"]),
        BloodMarker(key: "rdw", label: "I.D.R.", unit: "%", plausible: 8...35,
                    aliases: ["i.d.r.", "idr"]),
        BloodMarker(key: "white_blood_cells", label: "Leucocytes", unit: "G/L", plausible: 0.1...200,
                    aliases: ["leucocytes", "globules blancs"]),
        BloodMarker(key: "neutrophils", label: "Polynucléaires neutrophiles", unit: "G/L", plausible: 0...100,
                    aliases: ["polynucleaires neutrophiles", "neutrophiles"]),
        BloodMarker(key: "eosinophils", label: "Polynucléaires éosinophiles", unit: "G/L", plausible: 0...30,
                    aliases: ["polynucleaires eosinophiles", "eosinophiles"]),
        BloodMarker(key: "basophils", label: "Polynucléaires basophiles", unit: "G/L", plausible: 0...10,
                    aliases: ["polynucleaires basophiles", "basophiles"]),
        BloodMarker(key: "lymphocytes", label: "Lymphocytes", unit: "G/L", plausible: 0...150,
                    aliases: ["lymphocytes"]),
        BloodMarker(key: "monocytes", label: "Monocytes", unit: "G/L", plausible: 0...30,
                    aliases: ["monocytes"]),
        BloodMarker(key: "platelets", label: "Plaquettes", unit: "G/L", plausible: 5...2000,
                    aliases: ["plaquettes"]),
        BloodMarker(key: "mean_platelet_volume", label: "Volume plaquettaire moyen", unit: "fL", plausible: 4...20,
                    aliases: ["volume plaquettaire moyen", "v.p.m.", "vpm"]),
        BloodMarker(key: "creatinine", label: "Créatinine", unit: "mg/L", plausible: 1...200,
                    aliases: ["creatinine", "creatininemie"]),
        BloodMarker(key: "egfr", label: "DFG estimé (CKD-EPI)", unit: "mL/min/1,73m2", plausible: 2...200,
                    aliases: ["estimation du dfg", "dfg"]),
        BloodMarker(key: "ferritin", label: "Ferritine", unit: "µg/L", plausible: 1...10000,
                    aliases: ["ferritine", "ferritinemie"]),
        BloodMarker(key: "sodium", label: "Sodium", unit: "mmol/L", plausible: 100...180,
                    aliases: ["sodium", "natremie"]),
        BloodMarker(key: "potassium", label: "Potassium", unit: "mmol/L", plausible: 1.5...9,
                    aliases: ["potassium", "kaliemie"]),
        BloodMarker(key: "bilirubin_total", label: "Bilirubine totale", unit: "mg/L", plausible: 0.5...500,
                    aliases: ["bilirubine totale"]),
        BloodMarker(key: "alkaline_phosphatase", label: "Phosphatases alcalines", unit: "U/L", plausible: 5...3000,
                    aliases: ["phosphatases alcalines", "pal"]),
        BloodMarker(key: "ast", label: "ASAT", unit: "U/L", plausible: 1...10000,
                    aliases: ["asat", "transaminase s.g.o.t", "transaminases sgot", "tgo"]),
        BloodMarker(key: "alt", label: "ALAT", unit: "U/L", plausible: 1...10000,
                    aliases: ["alat", "transaminase s.g.p.t", "transaminases sgpt", "tgp"]),
        BloodMarker(key: "ggt", label: "GGT", unit: "U/L", plausible: 1...5000,
                    aliases: ["ggt", "gamma gt", "gamma glutamyl"]),
        BloodMarker(key: "glucose_fasting", label: "Glycémie à jeun", unit: "g/L", plausible: 0.2...10,
                    aliases: ["glycemie a jeun", "glycemie"]),
        BloodMarker(key: "triglycerides", label: "Triglycérides", unit: "g/L", plausible: 0.1...50,
                    aliases: ["triglycerides"]),
        BloodMarker(key: "cholesterol_total", label: "Cholestérol total", unit: "g/L", plausible: 0.3...10,
                    aliases: ["cholesterol total", "cholesterol"]),
        BloodMarker(key: "cholesterol_hdl", label: "Cholestérol HDL", unit: "g/L", plausible: 0.05...3,
                    aliases: ["cholesterol hdl", "hdl cholesterol"]),
        BloodMarker(key: "cholesterol_non_hdl", label: "Cholestérol non-HDL", unit: "g/L", plausible: 0.1...10,
                    aliases: ["cholesterol non-hdl", "cholesterol non hdl"]),
        BloodMarker(key: "cholesterol_ldl", label: "Cholestérol LDL calculé", unit: "g/L", plausible: 0.05...8,
                    aliases: ["cholesterol ldl", "ldl cholesterol"]),
        BloodMarker(key: "tsh", label: "TSH", unit: "mUI/L", plausible: 0.001...500,
                    aliases: ["tsh"]),
    ]

    static func marker(_ key: String) -> BloodMarker? {
        all.first { $0.key == key }
    }
}
