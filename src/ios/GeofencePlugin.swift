//
//  GeofencePlugin.swift
//  ionic-geofence
//
//  Created by tomasz on 07/10/14.
//
//
import Foundation
import AudioToolbox
import WebKit
import CoreLocation

let TAG = "GeofencePlugin"
let iOS8 = floor(NSFoundationVersionNumber) > floor(NSFoundationVersionNumber_iOS_7_1)
let iOS7 = floor(NSFoundationVersionNumber) <= floor(NSFoundationVersionNumber_iOS_7_1)
struct postBody: Codable {
    let eventType: Int
    var latitude: Double?
    var longitude: Double?
    let placeId: String
    var timeOfEvent: String
}

func log(_ message: String){
    NSLog("%@ - %@", TAG, message)
}

func log(_ messages: [String]) {
    for message in messages {
        log(message);
    }
}

@available(iOS 8.0, *)
@objc(HWPGeofencePlugin) class GeofencePlugin : CDVPlugin {
    lazy var geoNotificationManager = GeoNotificationManager()

    override func pluginInitialize () {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didReceiveLocalNotification(_:)),
            name: NSNotification.Name(rawValue: "CDVLocalNotification"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didReceiveTransition(_:)),
            name: NSNotification.Name(rawValue: "handleTransition"),
            object: nil
        )
    }

    @objc(initialize:)
    func initialize(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            log("Plugin initialization")
//            let faker = GeofenceFaker(manager: geoNotificationManager)
//            faker.start()
//            if iOS8 {
//                self.promptForNotificationPermission()
//            }
            self.geoNotificationManager = GeoNotificationManager()
            self.geoNotificationManager.evaluateJs = self.evaluateJs;
            self.geoNotificationManager.registerPermissions()

            let (ok, warnings, errors) = self.geoNotificationManager.checkRequirements()

            log(warnings)
            log(errors)

            let result: CDVPluginResult

            if ok {
                result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: warnings.joined(separator: "\n"))
            } else {
                result = CDVPluginResult(
                    status: CDVCommandStatus_ILLEGAL_ACCESS_EXCEPTION,
                    messageAs: (errors + warnings).joined(separator: "\n")
                )
            }

            self.commandDelegate!.send(result, callbackId: command.callbackId)
        }
    }

    @objc(deviceReady:)
    func deviceReady(_ command: CDVInvokedUrlCommand) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(ping:)
    func ping(_ command: CDVInvokedUrlCommand) {
        log("Ping")
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(promptForNotificationPermission)
    func promptForNotificationPermission() {
        UIApplication.shared.registerUserNotificationSettings(UIUserNotificationSettings(
            types: [UIUserNotificationType.sound, UIUserNotificationType.alert, UIUserNotificationType.badge],
            categories: nil
            )
        )
    }

    @objc(addOrUpdate:)
    func addOrUpdate(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            for geo in command.arguments {
                self.geoNotificationManager.addOrUpdateGeoNotification(JSON(geo))
            }
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        }
    }

    @objc(getWatched:)
    func getWatched(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global().async {
            let watched = self.geoNotificationManager.getWatchedGeoNotifications()!
            let watchedJsonString = watched.description
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: watchedJsonString)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }

    @objc(remove:)
    func remove(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global().async {
            for id in command.arguments {
                self.geoNotificationManager.removeGeoNotification(id as! String)
            }
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }

    @objc(removeAll:)
    func removeAll(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global().async {
            self.geoNotificationManager.removeAllGeoNotifications()
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }

    @objc func didReceiveTransition (_ notification: Notification) {
        log("didReceiveTransition")
        if let geoNotificationString = notification.object as? String {

            let js = "setTimeout(()=>{geofence.onTransitionReceived([" + geoNotificationString + "])},0)"

            evaluateJs(js)
        }
    }

    @objc func didReceiveLocalNotification (_ notification: Notification) {
        log("didReceiveLocalNotification")
        if UIApplication.shared.applicationState != UIApplication.State.active {
            var data = "undefined"
            if let uiNotification = notification.object as? UILocalNotification {
                if let notificationData = uiNotification.userInfo?["geofence.notification.data"] as? String {
                    data = notificationData
                }
                let js = "setTimeout(()=>{geofence.onNotificationClicked(" + data + ")},0)"

                evaluateJs(js)
            }
        }
    }

    func evaluateJs (_ script: String) {
        if let webView = webView {
            if let uiWebView = webView as? UIWebView {
                uiWebView.stringByEvaluatingJavaScript(from: script)
            } else if let wkWebView = webView as? WKWebView {
                wkWebView.evaluateJavaScript(script, completionHandler: nil)
            }
        } else {
            log("webView is nil")
        }
    }
}

// class for faking crossing geofences
@available(iOS 8.0, *)
class GeofenceFaker {
    let priority = DispatchQueue.GlobalQueuePriority.default
    let geoNotificationManager: GeoNotificationManager

    init(manager: GeoNotificationManager) {
        geoNotificationManager = manager
    }

    func start() {
        DispatchQueue.global(priority: priority).async {
            while (true) {
                log("FAKER")
                let notify = arc4random_uniform(4)
                if notify == 0 {
                    log("FAKER notify chosen, need to pick up some region")
                    var geos = self.geoNotificationManager.getWatchedGeoNotifications()!
                    if geos.count > 0 {
                        //WTF Swift??
                        let index = arc4random_uniform(UInt32(geos.count))
                        let geo = geos[Int(index)]
                        let id = geo["id"].stringValue
                        DispatchQueue.main.async {
                            if let region = self.geoNotificationManager.getMonitoredRegion(id) {
                                log("FAKER Trigger didEnterRegion")
                                self.geoNotificationManager.locationManager(
                                    self.geoNotificationManager.locationManager,
                                    didEnterRegion: region
                                )
                            }
                        }
                    }
                }
                Thread.sleep(forTimeInterval: 3)
            }
         }
    }

    func stop() {

    }
}

@available(iOS 8.0, *)
class GeoNotificationManager : NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    let store = GeoNotificationStore()
    var evaluateJs: ((String) -> Void)?

    override init() {
        log("GeoNotificationManager init")
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func registerPermissions() {
        if iOS8 {
            locationManager.requestAlwaysAuthorization()
        }
    }

    func addOrUpdateGeoNotification(_ geoNotification: JSON) {
        log("GeoNotificationManager addOrUpdate")

        let (_, warnings, errors) = checkRequirements()

        log(warnings)
        log(errors)

        let location = CLLocationCoordinate2DMake(
            geoNotification["latitude"].doubleValue,
            geoNotification["longitude"].doubleValue
        )
        log("AddOrUpdate geo: \(geoNotification)")
        let radius = geoNotification["radius"].doubleValue as CLLocationDistance
        let id = geoNotification["id"].stringValue

        let region = CLCircularRegion(center: location, radius: radius, identifier: id)

        var transitionType = 0
        if let i = geoNotification["transitionType"].int {
            transitionType = i
        }
        region.notifyOnEntry = 0 != transitionType & 1
        region.notifyOnExit = 0 != transitionType & 2

        //store
        store.addOrUpdate(geoNotification)
        locationManager.startMonitoring(for: region)
        locationManager.startUpdatingLocation()
    }

    func checkRequirements() -> (Bool, [String], [String]) {
        var errors = [String]()
        var warnings = [String]()

        if (!CLLocationManager.isMonitoringAvailable(for: CLRegion.self)) {
            errors.append("Geofencing not available")
        }

        if (!CLLocationManager.locationServicesEnabled()) {
            errors.append("Error: Locationservices not enabled")
        }

        let authStatus = CLLocationManager.authorizationStatus()

        if (authStatus != CLAuthorizationStatus.authorizedAlways && authStatus != CLAuthorizationStatus.authorizedWhenInUse) {
            errors.append("Warning: Location permissions not granted")
        }

//        if (iOS8) {
//            if let notificationSettings = UIApplication.shared.currentUserNotificationSettings {
//                if notificationSettings.types == UIUserNotificationType() {
//                    errors.append("Error: notification permission missing")
//                } else {
//                    if !notificationSettings.types.contains(.sound) {
//                        warnings.append("Warning: notification settings - sound permission missing")
//                    }
//
//                    if !notificationSettings.types.contains(.alert) {
//                        warnings.append("Warning: notification settings - alert permission missing")
//                    }
//
//                    if !notificationSettings.types.contains(.badge) {
//                        warnings.append("Warning: notification settings - badge permission missing")
//                    }
//                }
//            } else {
//                errors.append("Error: notification permission missing")
//            }
//        }
        let ok = (errors.count == 0)

        return (ok, warnings, errors)
    }

    func getWatchedGeoNotifications() -> [JSON]? {
        return store.getAll()
    }

    func getMonitoredRegion(_ id: String) -> CLRegion? {
        for object in locationManager.monitoredRegions {
            let region = object

            if (region.identifier == id) {
                return region
            }
        }
        return nil
    }

    func removeGeoNotification(_ id: String) {
        store.remove(id)
        let region = getMonitoredRegion(id)
        if (region != nil) {
            log("Stoping monitoring region \(id)")
            locationManager.stopMonitoring(for: region!)
        }
    }

    func removeAllGeoNotifications() {
        store.clear()
        for object in locationManager.monitoredRegions {
            let region = object
            log("Stoping monitoring region \(region.identifier)")
            locationManager.stopMonitoring(for: region)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {        
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log("fail with error: \(error)")
    }

    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        log("deferred fail error: \(error)")
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        log("Entering region \(region.identifier)")
        handleTransition(region, transitionType: 1)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        log("Exiting region \(region.identifier)")
        handleTransition(region, transitionType: 2)
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        if region is CLCircularRegion {
            let lat = (region as! CLCircularRegion).center.latitude
            let lng = (region as! CLCircularRegion).center.longitude
            let radius = (region as! CLCircularRegion).radius

            log("Starting monitoring for region \(region) lat \(lat) lng \(lng) of radius \(radius)")
            locationManager.requestState(for: region)
        }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        log("State for region " + region.identifier)
        switch state{
        case .inside:
            handleTransition(region, transitionType: 1)
            break
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        log("Monitoring region " + region!.identifier + " failed \(error)" )
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
            case .authorizedAlways:
                // The user accepted the location permission popup. Notify TypeScript to add the geofences into this plugin.
                self.evaluateJs?("setTimeout(()=>{geofence.onLocationPermissionAuthorized()},0)")
                break
            case .notDetermined:
                break
            case .denied:
                break
            case .restricted:
                break
            case .authorizedWhenInUse:
                break
        }
    }

    func handleTransition(_ region: CLRegion!, transitionType: Int) {
        if var geoNotification = store.findById(region.identifier) {
            geoNotification["transitionType"].int = transitionType

            if geoNotification["notification"].isExists() {
                callUrl(geo: geoNotification, transitionType: transitionType)
                //notifyAbout(geoNotification)
            }
            NotificationCenter.default.post(name: Notification.Name(rawValue: "handleTransition"), object: geoNotification.rawString(String.Encoding.utf8.rawValue, options: []))
        }
    }

    /* This should call the URL with method (eg POST) and postData */
    func callUrl(geo: JSON, transitionType: Int) {
        let method = "POST";
        let url = geo["notification"]["url"].stringValue;
        let deviceToken = geo["notification"]["deviceToken"].stringValue;
        let corpProp = geo["notification"]["corpProp"].stringValue;
        let clientID = geo["notification"]["clientID"].stringValue;
        var postData = geo["notification"]["bodyEnter"].stringValue;
        if (transitionType == 2) {
            postData = geo["notification"]["bodyExit"].stringValue;
        }

        do {
            let jsonDecoder = JSONDecoder()
            var decodedData = try jsonDecoder.decode(postBody.self, from: postData.data(using: String.Encoding.utf8)!)
            let date = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            formatter.timeZone = TimeZone.current
            decodedData.timeOfEvent = formatter.string(from: date);
            decodedData.latitude = locationManager.location!.coordinate.latitude
            decodedData.longitude = locationManager.location!.coordinate.longitude
            let jsonEncoder = JSONEncoder()
            let encodedData = try jsonEncoder.encode(decodedData)
            postData = String(data: encodedData, encoding: String.Encoding.utf8)!.replacingOccurrences(of: "\\/", with: "/")
        } catch {}

        let token = geo["notification"]["token"].stringValue;
        log("callUrl "+url+" "+postData)
        let urlString = url;
        guard let endpointUrl = URL(string: urlString) else {
            return
        }

        var request = URLRequest(url: endpointUrl)
        request.httpMethod = method
        request.httpBody = postData.data(using: String.Encoding.utf8);
        request.addValue("application/json", forHTTPHeaderField: "Content-Type");
        request.addValue("*/*", forHTTPHeaderField: "Accept");
        request.addValue(token, forHTTPHeaderField: "Token");
        request.addValue(deviceToken, forHTTPHeaderField: "DeviceToken");
        request.addValue(clientID, forHTTPHeaderField: "Client-ID");
        request.addValue(corpProp, forHTTPHeaderField: "CorpProp");

        let task = URLSession.shared.dataTask(with: request) {
            (data, response, error) in
            guard error == nil else {
                log("failed to call "+url);
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                log("callUrl Returned: \(httpResponse.statusCode)")
            }
        }
        task.resume()
    }

    func notifyAbout(_ geo: JSON) {
        log("Creating notification")
        let notification = UILocalNotification()
        notification.timeZone = TimeZone.current
        let dateTime = Date()
        notification.fireDate = dateTime
        notification.soundName = UILocalNotificationDefaultSoundName
        notification.alertBody = geo["notification"]["text"].stringValue
        if let json = geo["notification"]["data"] as JSON? {
            notification.userInfo = ["geofence.notification.data": json.rawString(String.Encoding.utf8.rawValue, options: [])!]
        }
        UIApplication.shared.scheduleLocalNotification(notification)

        if let vibrate = geo["notification"]["vibrate"].array {
            if (!vibrate.isEmpty && vibrate[0].intValue > 0) {
                AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
            }
        }
    }
}

class GeoNotificationStore {
    init() {
        createDBStructure()
    }

    func createDBStructure() {
        let (tables, err) = SD.existingTables()

        if (err != nil) {
            log("Cannot fetch sqlite tables: \(err)")
            return
        }

        if (tables.filter { $0 == "GeoNotifications" }.count == 0) {
            if let err = SD.executeChange("CREATE TABLE GeoNotifications (ID TEXT PRIMARY KEY, Data TEXT)") {
                //there was an error during this function, handle it here
                log("Error while creating GeoNotifications table: \(err)")
            } else {
                //no error, the table was created successfully
                log("GeoNotifications table was created successfully")
            }
        }
    }

    func addOrUpdate(_ geoNotification: JSON) {
        if (findById(geoNotification["id"].stringValue) != nil) {
            update(geoNotification)
        }
        else {
            add(geoNotification)
        }
    }

    func add(_ geoNotification: JSON) {
        let id = geoNotification["id"].stringValue
        let err = SD.executeChange("INSERT INTO GeoNotifications (Id, Data) VALUES(?, ?)",
            withArgs: [id as AnyObject, geoNotification.description as AnyObject])

        if err != nil {
            log("Error while adding \(id) GeoNotification: \(err)")
        }
    }

    func update(_ geoNotification: JSON) {
        let id = geoNotification["id"].stringValue
        let err = SD.executeChange("UPDATE GeoNotifications SET Data = ? WHERE Id = ?",
            withArgs: [geoNotification.description as AnyObject, id as AnyObject])

        if err != nil {
            log("Error while adding \(id) GeoNotification: \(err)")
        }
    }

    func findById(_ id: String) -> JSON? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications WHERE Id = ?", withArgs: [id as AnyObject])

        if err != nil {
            //there was an error during the query, handle it here
            log("Error while fetching \(id) GeoNotification table: \(err)")
            return nil
        } else {
            if (resultSet.count > 0) {
                let jsonString = resultSet[0]["Data"]!.asString()!
                return JSON(data: jsonString.data(using: String.Encoding.utf8)!)
            }
            else {
                return nil
            }
        }
    }

    func getAll() -> [JSON]? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications")

        if err != nil {
            //there was an error during the query, handle it here
            log("Error while fetching from GeoNotifications table: \(err)")
            return nil
        } else {
            var results = [JSON]()
            for row in resultSet {
                if let data = row["Data"]?.asString() {
                    results.append(JSON(data: data.data(using: String.Encoding.utf8)!))
                }
            }
            return results
        }
    }

    func remove(_ id: String) {
        let err = SD.executeChange("DELETE FROM GeoNotifications WHERE Id = ?", withArgs: [id as AnyObject])

        if err != nil {
            log("Error while removing \(id) GeoNotification: \(err)")
        }
    }

    func clear() {
        let err = SD.executeChange("DELETE FROM GeoNotifications")

        if err != nil {
            log("Error while deleting all from GeoNotifications: \(err)")
        }
    }
}