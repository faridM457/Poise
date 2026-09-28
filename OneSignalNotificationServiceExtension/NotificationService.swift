//
//  NotificationService.swift
//  OneSignalNotificationServiceExtension
//
//  Created by Rafid Mohammed on 9/26/26.
//  Copyright © 2026 Saper Solutions. All rights reserved.
//

import OneSignalExtension
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var receivedRequest: UNNotificationRequest?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        receivedRequest = request
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }
        OneSignalExtension.didReceiveNotificationExtensionRequest(
            request,
            with: bestAttemptContent,
            withContentHandler: contentHandler
        )
    }

    override func serviceExtensionTimeWillExpire() {
        guard let receivedRequest, let bestAttemptContent, let contentHandler else { return }
        OneSignalExtension.serviceExtensionTimeWillExpireRequest(
            receivedRequest,
            with: bestAttemptContent
        )
        contentHandler(bestAttemptContent)
    }
}
