import Foundation
import SwiftUI

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published var subscriptions: [Subscription] = []

    init() {
        subscriptions = StorageService.shared.loadSubscriptions()
    }

    func add(_ data: SubscriptionFormData) {
        guard let amount = data.parsedAmount else { return }

        let sub = Subscription(
            id: UUID(),
            name: data.name.trimmingCharacters(in: .whitespaces),
            url: data.url.isEmpty ? nil : data.url,
            logo: data.logo,
            amount: amount,
            currency: data.currency,
            cycle: data.cycle,
            billingDay: data.billingDay,
            startDate: data.startDate,
            trialEndDate: data.status == .trial ? data.trialEndDate : nil,
            category: data.category,
            status: data.status,
            notes: data.notes.isEmpty ? nil : data.notes,
            createdAt: Date(),
            updatedAt: Date()
        )

        subscriptions.append(sub)
        save()
    }

    func update(id: UUID, with data: SubscriptionFormData) {
        guard let amount = data.parsedAmount,
              let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }

        subscriptions[index].name = data.name.trimmingCharacters(in: .whitespaces)
        subscriptions[index].url = data.url.isEmpty ? nil : data.url
        subscriptions[index].logo = data.logo
        subscriptions[index].amount = amount
        subscriptions[index].currency = data.currency
        subscriptions[index].cycle = data.cycle
        subscriptions[index].billingDay = data.billingDay
        subscriptions[index].startDate = data.startDate
        subscriptions[index].trialEndDate = data.status == .trial ? data.trialEndDate : nil
        subscriptions[index].category = data.category
        subscriptions[index].status = data.status
        subscriptions[index].notes = data.notes.isEmpty ? nil : data.notes
        subscriptions[index].updatedAt = Date()
        save()
    }

    func delete(id: UUID) {
        subscriptions.removeAll { $0.id == id }
        save()
    }

    func togglePause(id: UUID) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].status = subscriptions[index].status == .active ? .paused : .active
        subscriptions[index].updatedAt = Date()
        save()
    }

    func clearAll() {
        subscriptions.removeAll()
        save()
    }

    func importSubscriptions(_ subs: [Subscription]) {
        subscriptions = subs
        save()
    }

    private func save() {
        StorageService.shared.saveSubscriptions(subscriptions)
    }
}
