import Foundation
import Observation
import StoreKit

/// The App Store products of SharpIt Pro. They must exist under these identifiers in App Store
/// Connect (subscription group « SharpIt Pro ») and in `Config/SharpitPro.storekit`, which the
/// simulator uses to buy without App Store Connect.
nonisolated enum SharpitProProduct {
    static let monthly = "app.sharpit.ios.pro.monthly"
    static let yearly = "app.sharpit.ios.pro.yearly"
    static let all = [monthly, yearly]
}

/// SharpIt Pro on the phone (SHARPIT ADR-044): what the web says the athlete has, and every
/// StoreKit transaction handed to the web to verify.
///
/// The app never decides the tier. A purchase, a renewal seen on launch or a restore sends the
/// signed transaction to `/api/v1/billing/apple/verify`; the web checks Apple's signature,
/// stores the subscription, derives the tier and answers with `/api/v1/pro`. A transaction is
/// finished only once the web has it, so an interrupted round-trip is retried by StoreKit.
@MainActor
@Observable
final class ProStore {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var pro: V1Pro?
    /// Carried by every purchase so Apple's notifications name this account.
    private(set) var appAccountToken: UUID?
    private(set) var isRestoring = false
    private(set) var message: String?

    private let client: any ProServing
    private let tokenProvider: () async throws -> String
    private var listening = false

    init(client: any ProServing = ProClient(), tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    var isPro: Bool { pro?.isPro ?? false }

    var proPerks: [V1ProPerk] { pro?.perks.filter { $0.status == .pro } ?? [] }
    var includedPerks: [V1ProPerk] { pro?.perks.filter { $0.status == .included } ?? [] }
    var plannedPerks: [V1ProPerk] { pro?.perks.filter { $0.status == .planned } ?? [] }

    /// Whether the subscription is managed through the App Store (and so from this iPhone).
    var isAppleSubscription: Bool { pro?.subscription?.source == "apple" }

    func load() async {
        do {
            let token = try await tokenProvider()
            let fetched = try await client.pro(token: token)
            SharpitMotion.run {
                pro = fetched
                phase = .loaded
            }
            if appAccountToken == nil {
                appAccountToken = try? await client.appAccountToken(token: token)
            }
        } catch {
            if pro == nil { phase = .failed("SharpIt Pro est indisponible pour le moment.") }
        }
    }

    /// Hands a StoreKit result to the web, then finishes it. An unverified transaction — one
    /// StoreKit itself could not vouch for — is never sent.
    func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            message = "Achat non vérifié par l'App Store."
            return
        }
        let renewal = await renewalInfo(for: transaction)
        do {
            let token = try await tokenProvider()
            let verified = try await client.verify(
                signedTransaction: result.jwsRepresentation,
                signedRenewalInfo: renewal,
                token: token
            )
            await transaction.finish()
            SharpitMotion.run {
                pro = verified
                phase = .loaded
            }
            message = nil
        } catch SharpitAPIError.badRequest {
            // Refused by the web (another account's purchase, a forged receipt): finished so
            // StoreKit stops offering it, never granted.
            await transaction.finish()
            message = "Cet achat est rattaché à un autre compte."
        } catch {
            message = "L'abonnement sera confirmé dès que le serveur répondra."
        }
    }

    /// Asks the App Store for this Apple Account's purchases and sends each current one to the web.
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            message = "Restauration annulée."
            return
        }
        var found = false
        for await entitlement in Transaction.currentEntitlements {
            found = true
            await handle(entitlement)
        }
        if !found { message = "Aucun abonnement à restaurer sur ce compte Apple." }
        await load()
    }

    /// Renewals, refunds and purchases made elsewhere (another device, Family Sharing, the
    /// App Store's own screens) arrive here while the app runs. Started once at launch.
    func listenForTransactions() async {
        guard !listening else { return }
        listening = true
        for await unfinished in Transaction.unfinished {
            await handle(unfinished)
        }
        for await update in Transaction.updates {
            await handle(update)
        }
    }

    private func renewalInfo(for transaction: Transaction) async -> String? {
        guard let status = await transaction.subscriptionStatus else { return nil }
        return status.renewalInfo.jwsRepresentation
    }
}

/// How the subscription reads, in the athlete's words.
nonisolated enum ProReadout {
    static func status(_ subscription: V1ProSubscription?, isPro: Bool) -> String {
        guard let subscription else {
            return isPro ? "Accès Pro offert" : "Version gratuite"
        }
        switch subscription.status {
        case "active":
            if subscription.willRenew, let renews = subscription.renewsAt ?? subscription.expiresAt {
                return "Renouvellement le \(day(renews))"
            }
            if let expires = subscription.expiresAt {
                return "Actif jusqu'au \(day(expires))"
            }
            return "Actif"
        case "grace_period":
            return "Paiement en attente — l'accès est maintenu"
        case "billing_retry":
            return "Paiement refusé — mets à jour ton moyen de paiement"
        case "revoked":
            return "Abonnement remboursé"
        default:
            if let expires = subscription.expiresAt { return "Expiré le \(day(expires))" }
            return "Expiré"
        }
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR")))
    }
}
