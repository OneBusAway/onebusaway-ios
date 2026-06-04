# Live Activity Push Notifications Guide

This document explains how to implement real-time Live Activity updates (~60 second refresh) for OneBusAway iOS using ActivityKit push notifications.

## Overview

Live Activities cannot update themselves in the background. The only reliable way to achieve frequent updates (~60 seconds) is through **ActivityKit push notifications** sent from a server to Apple Push Notification service (APNs).

### Update Frequency Options

| Approach | `apns-priority` | Budget | Use Case |
|----------|-----------------|--------|----------|
| Standard | `10` (high) | ~4/hour | Critical updates (delays, cancellations) |
| Low Priority | `5` | Unlimited | Routine updates (countdown refresh) |
| Frequent Updates | `10` | Higher budget | Real-time tracking (requires entitlement) |

For ~60 second updates, you need the **Frequent Updates entitlement** (`NSSupportsLiveActivitiesFrequentUpdates`).

---

## Implementation Steps

### 1. Configure Info.plist

Add these keys to your app's `Info.plist`:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

### 2. Add Push Notifications Capability

In Xcode:
1. Select your app target
2. Go to **Signing & Capabilities**
3. Click **+ Capability**
4. Add **Push Notifications**

### 3. Define Activity Attributes

```swift
import ActivityKit

struct DepartureAttributes: ActivityAttributes {
    // Static data (doesn't change during the activity)
    let stopId: String
    let stopName: String
    let routeId: String
    let routeShortName: String
    let tripHeadsign: String

    // Dynamic data (updated via push notifications)
    struct ContentState: Codable, Hashable {
        let predictedArrival: Date
        let scheduledArrival: Date
        let minutesUntilDeparture: Int
        let isDelayed: Bool
        let delayMinutes: Int?
        let vehicleId: String?
        let occupancyStatus: String?
    }
}
```

### 4. Start Live Activity with Push Token

```swift
import ActivityKit

class LiveActivityManager {

    func startDepartureActivity(
        stop: Stop,
        arrivalDeparture: ArrivalDeparture
    ) async throws -> Activity<DepartureAttributes> {

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.notAuthorized
        }

        let attributes = DepartureAttributes(
            stopId: stop.id,
            stopName: stop.name,
            routeId: arrivalDeparture.routeId,
            routeShortName: arrivalDeparture.routeShortName,
            tripHeadsign: arrivalDeparture.tripHeadsign
        )

        let initialState = DepartureAttributes.ContentState(
            predictedArrival: arrivalDeparture.predictedArrivalTime,
            scheduledArrival: arrivalDeparture.scheduledArrivalTime,
            minutesUntilDeparture: arrivalDeparture.minutesUntilDeparture,
            isDelayed: arrivalDeparture.isDelayed,
            delayMinutes: arrivalDeparture.delayMinutes,
            vehicleId: arrivalDeparture.vehicleId,
            occupancyStatus: arrivalDeparture.occupancyStatus
        )

        let content = ActivityContent(
            state: initialState,
            staleDate: Date().addingTimeInterval(2 * 60) // Stale after 2 minutes
        )

        // Request activity with push token support
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: .token  // Enable push notifications
        )

        // Observe and send push token to server
        Task {
            for await pushToken in activity.pushTokenUpdates {
                let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
                await sendPushTokenToServer(
                    token: tokenString,
                    tripId: arrivalDeparture.tripId,
                    stopId: stop.id
                )
            }
        }

        return activity
    }

    private func sendPushTokenToServer(token: String, tripId: String, stopId: String) async {
        // Send to your server endpoint
        let payload: [String: Any] = [
            "pushToken": token,
            "tripId": tripId,
            "stopId": stopId,
            "platform": "ios"
        ]

        // POST to your server
        // await apiService.registerLiveActivityToken(payload)
    }
}
```

### 5. Check Frequent Updates Permission

Users can disable frequent updates in Settings. Check and handle this:

```swift
class LiveActivityManager {

    var canUseFrequentUpdates: Bool {
        ActivityAuthorizationInfo().frequentPushesEnabled
    }

    func observeFrequentPushSettings() {
        Task {
            for await enabled in ActivityAuthorizationInfo().frequentPushEnablementUpdates {
                if !enabled {
                    // Notify server to reduce update frequency
                    await notifyServerFrequentUpdatesDisabled()
                }
            }
        }
    }
}
```

### 6. Handle Activity Lifecycle

```swift
extension LiveActivityManager {

    /// Update activity from app (when foregrounded)
    func updateActivity(
        _ activity: Activity<DepartureAttributes>,
        with newState: DepartureAttributes.ContentState,
        alertConfiguration: AlertConfiguration? = nil
    ) async {
        let content = ActivityContent(
            state: newState,
            staleDate: Date().addingTimeInterval(2 * 60)
        )

        await activity.update(content, alertConfiguration: alertConfiguration)
    }

    /// End activity
    func endActivity(
        _ activity: Activity<DepartureAttributes>,
        finalState: DepartureAttributes.ContentState,
        dismissImmediately: Bool = false
    ) async {
        let content = ActivityContent(
            state: finalState,
            staleDate: nil
        )

        let dismissalPolicy: ActivityUIDismissalPolicy = dismissImmediately
            ? .immediate
            : .default

        await activity.end(content, dismissalPolicy: dismissalPolicy)
    }

    /// Get all active departure activities
    var activeActivities: [Activity<DepartureAttributes>] {
        Activity<DepartureAttributes>.activities
    }
}
```

---

## Server Implementation

### Push Notification Requirements

Your server must send HTTP/2 requests to APNs with specific headers:

| Header | Value |
|--------|-------|
| `apns-topic` | `com.yourapp.bundleid.push-type.liveactivity` |
| `apns-push-type` | `liveactivity` |
| `apns-priority` | `5` (low) or `10` (high) |
| `authorization` | `bearer <JWT_TOKEN>` |

### JSON Payload Structure

#### Update Payload

```json
{
    "aps": {
        "timestamp": 1706198400,
        "event": "update",
        "content-state": {
            "predictedArrival": 1706199000,
            "scheduledArrival": 1706198700,
            "minutesUntilDeparture": 8,
            "isDelayed": true,
            "delayMinutes": 5,
            "vehicleId": "1234",
            "occupancyStatus": "MANY_SEATS_AVAILABLE"
        },
        "stale-date": 1706198520,
        "relevance-score": 100
    }
}
```

#### Update with Alert (for significant changes)

```json
{
    "aps": {
        "timestamp": 1706198400,
        "event": "update",
        "content-state": {
            "predictedArrival": 1706199600,
            "scheduledArrival": 1706198700,
            "minutesUntilDeparture": 18,
            "isDelayed": true,
            "delayMinutes": 15,
            "vehicleId": "1234",
            "occupancyStatus": null
        },
        "alert": {
            "title": "Route 36 Delayed",
            "body": "Now arriving in 18 minutes (15 min delay)",
            "sound": "default"
        }
    }
}
```

#### End Payload

```json
{
    "aps": {
        "timestamp": 1706199000,
        "event": "end",
        "dismissal-date": 1706199300,
        "content-state": {
            "predictedArrival": 1706199000,
            "scheduledArrival": 1706198700,
            "minutesUntilDeparture": 0,
            "isDelayed": true,
            "delayMinutes": 5,
            "vehicleId": "1234",
            "occupancyStatus": "FULL"
        }
    }
}
```

### Server Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        OBA Server                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │   REST API   │    │  Scheduler   │    │  Push Service    │  │
│  │              │    │  (60 sec)    │    │                  │  │
│  │ POST /live-  │    │              │    │  - JWT signing   │  │
│  │ activity/    │───▶│  For each    │───▶│  - HTTP/2 client │  │
│  │ register     │    │  active      │    │  - APNs connect  │  │
│  │              │    │  activity:   │    │                  │  │
│  └──────────────┘    │  fetch data  │    └────────┬─────────┘  │
│                      │  send push   │             │            │
│  ┌──────────────┐    └──────────────┘             │            │
│  │   Database   │                                 │            │
│  │              │                                 ▼            │
│  │ - tokens     │                        ┌───────────────┐    │
│  │ - tripIds    │                        │     APNs      │    │
│  │ - stopIds    │                        │               │    │
│  └──────────────┘                        └───────┬───────┘    │
│                                                  │            │
└──────────────────────────────────────────────────┼────────────┘
                                                   │
                                                   ▼
                                          ┌───────────────┐
                                          │   iOS Device  │
                                          │               │
                                          │ Live Activity │
                                          │   Updated!    │
                                          └───────────────┘
```

### Example Server Code (Node.js)

```javascript
const http2 = require('http2');
const jwt = require('jsonwebtoken');
const fs = require('fs');

class APNsService {
    constructor(config) {
        this.teamId = config.teamId;
        this.keyId = config.keyId;
        this.privateKey = fs.readFileSync(config.privateKeyPath);
        this.bundleId = config.bundleId;
        this.isProduction = config.isProduction;
    }

    getJWT() {
        const token = jwt.sign(
            { iss: this.teamId, iat: Math.floor(Date.now() / 1000) },
            this.privateKey,
            { algorithm: 'ES256', header: { alg: 'ES256', kid: this.keyId } }
        );
        return token;
    }

    async sendLiveActivityUpdate(pushToken, contentState, options = {}) {
        const host = this.isProduction
            ? 'api.push.apple.com'
            : 'api.sandbox.push.apple.com';

        const payload = {
            aps: {
                timestamp: Math.floor(Date.now() / 1000),
                event: options.event || 'update',
                'content-state': contentState,
                'stale-date': Math.floor(Date.now() / 1000) + 120, // 2 min
                'relevance-score': options.relevanceScore || 100
            }
        };

        if (options.alert) {
            payload.aps.alert = options.alert;
        }

        if (options.dismissalDate) {
            payload.aps['dismissal-date'] = options.dismissalDate;
        }

        return new Promise((resolve, reject) => {
            const client = http2.connect(`https://${host}`);

            const headers = {
                ':method': 'POST',
                ':path': `/3/device/${pushToken}`,
                'apns-topic': `${this.bundleId}.push-type.liveactivity`,
                'apns-push-type': 'liveactivity',
                'apns-priority': options.priority || '5', // Use 5 for routine updates
                'authorization': `bearer ${this.getJWT()}`
            };

            const req = client.request(headers);

            req.on('response', (headers) => {
                const status = headers[':status'];
                if (status === 200) {
                    resolve({ success: true });
                } else {
                    reject({ success: false, status });
                }
            });

            req.write(JSON.stringify(payload));
            req.end();
        });
    }
}

// Scheduler - runs every 60 seconds
class LiveActivityScheduler {
    constructor(apnsService, database, obaApi) {
        this.apns = apnsService;
        this.db = database;
        this.obaApi = obaApi;
    }

    async start() {
        setInterval(() => this.updateAllActivities(), 60 * 1000);
    }

    async updateAllActivities() {
        const activeTokens = await this.db.getActiveLiveActivityTokens();

        for (const record of activeTokens) {
            try {
                // Fetch latest arrival data from OBA API
                const arrival = await this.obaApi.getArrivalForTrip(
                    record.tripId,
                    record.stopId
                );

                if (!arrival) {
                    // Trip completed, end the activity
                    await this.endActivity(record);
                    continue;
                }

                const contentState = {
                    predictedArrival: Math.floor(arrival.predictedTime / 1000),
                    scheduledArrival: Math.floor(arrival.scheduledTime / 1000),
                    minutesUntilDeparture: arrival.minutesUntilDeparture,
                    isDelayed: arrival.predicted && arrival.predictedTime > arrival.scheduledTime,
                    delayMinutes: Math.floor((arrival.predictedTime - arrival.scheduledTime) / 60000),
                    vehicleId: arrival.vehicleId,
                    occupancyStatus: arrival.occupancyStatus
                };

                // Check for significant delay change to send alert
                const alert = this.shouldAlert(record.lastState, contentState)
                    ? { title: 'Delay Update', body: `Now ${contentState.minutesUntilDeparture} min` }
                    : undefined;

                await this.apns.sendLiveActivityUpdate(
                    record.pushToken,
                    contentState,
                    {
                        priority: alert ? '10' : '5',
                        alert
                    }
                );

                // Update last known state
                await this.db.updateLastState(record.id, contentState);

            } catch (error) {
                console.error(`Failed to update activity ${record.id}:`, error);
            }
        }
    }

    shouldAlert(previousState, newState) {
        if (!previousState) return false;

        // Alert if delay increased by 5+ minutes
        const prevDelay = previousState.delayMinutes || 0;
        const newDelay = newState.delayMinutes || 0;

        return (newDelay - prevDelay) >= 5;
    }

    async endActivity(record) {
        await this.apns.sendLiveActivityUpdate(
            record.pushToken,
            record.lastState,
            {
                event: 'end',
                dismissalDate: Math.floor(Date.now() / 1000) + 300 // Remove after 5 min
            }
        );
        await this.db.removeLiveActivityToken(record.id);
    }
}
```

---

## Live Activity Widget UI

### Widget Extension Code

```swift
import WidgetKit
import SwiftUI

struct DepartureActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureAttributes.self) { context in
            // Lock Screen / Banner presentation
            LockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    RouteLabel(routeName: context.attributes.routeShortName)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownView(arrival: context.state.predictedArrival)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.tripHeadsign)
                            .font(.caption)
                        Spacer()
                        if context.state.isDelayed {
                            DelayBadge(minutes: context.state.delayMinutes ?? 0)
                        }
                    }
                }
            } compactLeading: {
                RouteLabel(routeName: context.attributes.routeShortName)
            } compactTrailing: {
                // Auto-updating countdown timer
                Text(context.state.predictedArrival, style: .timer)
                    .monospacedDigit()
                    .frame(width: 50)
            } minimal: {
                Text(context.state.predictedArrival, style: .timer)
                    .monospacedDigit()
            }
        }
    }
}

struct LockScreenView: View {
    let context: ActivityViewContext<DepartureAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RouteLabel(routeName: context.attributes.routeShortName)

                Spacer()

                // Auto-updating relative time
                Text(context.state.predictedArrival, style: .relative)
                    .font(.title2.bold())
                    .monospacedDigit()
            }

            HStack {
                Text(context.attributes.tripHeadsign)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if context.state.isDelayed, let delay = context.state.delayMinutes {
                    Text("\(delay) min late")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if context.isStale {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                }
            }

            if let occupancy = context.state.occupancyStatus {
                OccupancyIndicator(status: occupancy)
            }
        }
        .padding()
    }
}

struct RouteLabel: View {
    let routeName: String

    var body: some View {
        Text(routeName)
            .font(.headline.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct CountdownView: View {
    let arrival: Date

    var body: some View {
        VStack(alignment: .trailing) {
            // This updates automatically every second!
            Text(arrival, style: .relative)
                .font(.title3.bold())
                .monospacedDigit()
        }
    }
}

struct DelayBadge: View {
    let minutes: Int

    var body: some View {
        Text("+\(minutes)m")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red)
            .clipShape(Capsule())
    }
}
```

---

## Testing

### Local Testing with curl

1. Start a Live Activity in your app and log the push token
2. Set environment variables:

```bash
export ACTIVITY_PUSH_TOKEN="your_push_token_here"
export AUTHENTICATION_TOKEN="your_jwt_token_here"
export BUNDLE_ID="com.onebusaway.iphone"
```

3. Send test update:

```bash
curl -v \
  --header "apns-topic: ${BUNDLE_ID}.push-type.liveactivity" \
  --header "apns-push-type: liveactivity" \
  --header "apns-priority: 10" \
  --header "authorization: bearer ${AUTHENTICATION_TOKEN}" \
  --data '{
    "aps": {
      "timestamp": '$(date +%s)',
      "event": "update",
      "content-state": {
        "predictedArrival": '$(date -v+8M +%s)',
        "scheduledArrival": '$(date -v+5M +%s)',
        "minutesUntilDeparture": 8,
        "isDelayed": true,
        "delayMinutes": 3,
        "vehicleId": "1234",
        "occupancyStatus": "MANY_SEATS_AVAILABLE"
      }
    }
  }' \
  --http2 \
  https://api.sandbox.push.apple.com/3/device/${ACTIVITY_PUSH_TOKEN}
```

### Using Push Notification Console

Apple provides a [Push Notification Console](https://developer.apple.com/notifications/push-notifications-console/) for testing without writing server code.

---

## Best Practices

### 1. Priority Strategy

```
60-second routine updates    → apns-priority: 5 (doesn't count toward budget)
Significant delay changes    → apns-priority: 10 + alert
Arrival imminent (< 2 min)   → apns-priority: 10
Trip cancelled               → apns-priority: 10 + alert + end
```

### 2. Handle Stale Data

Always set `stale-date` to ~2 minutes after each update:

```json
{
    "aps": {
        "timestamp": 1706198400,
        "stale-date": 1706198520,
        ...
    }
}
```

### 3. Graceful Degradation

If push fails or user disables frequent updates, fall back to `Text(date, style: .relative)` which auto-updates:

```swift
// In your widget view:
if context.isStale {
    // Show stale indicator but keep counting down
    Text(context.state.predictedArrival, style: .relative)
        .foregroundStyle(.secondary)
    Text("Tap to refresh")
        .font(.caption2)
} else {
    Text(context.state.predictedArrival, style: .relative)
}
```

### 4. Token Management

- Store tokens with associated trip/stop IDs
- Handle token updates (they can change)
- Remove tokens when activities end
- Invalidate tokens when trips complete

### 5. Battery Considerations

Even with frequent updates enabled, be mindful:
- Use `apns-priority: 5` for routine updates
- Reserve `apns-priority: 10` for important changes
- End activities promptly when trips complete
- Respect user's frequent update settings

---

## References

- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Starting and updating Live Activities with ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- [NSSupportsLiveActivitiesFrequentUpdates](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSSupportsLiveActivitiesFrequentUpdates)
- [Emoji Rangers Sample Code](https://developer.apple.com/documentation/WidgetKit/emoji-rangers-supporting-live-activities-interactivity-and-animations)
- [Sending push notifications using command-line tools](https://developer.apple.com/documentation/UserNotifications/sending-push-notifications-using-command-line-tools)
