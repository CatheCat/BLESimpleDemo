//
//  MasterViewController.swift
//  BLEDemo
//
//  Created by Catherine on 2016/10/12.
//  Copyright © 2016年 Catherine. All rights reserved.
//

import UIKit
import CoreBluetooth

let target_characteristic_uuid = "ffe1" // KentDingle
let sensor_characteristic_uuid = "dfd1" // Bluno

class MasterViewController: UITableViewController, CBCentralManagerDelegate, CBPeripheralDelegate {

    var detailViewController: DetailViewController? = nil
    var allItems = [String:DiscoveredItem](); //store all discoverd peripheral
    var lastReloadDate:Date?
    var objects = [Any]()
    // For Service/Characteristic scan
    var detailInfo = ""
    var restServices = [CBService]()
    var centralManager: CBCentralManager? //?表示可選型別，可能回傳是空
    
    // For Talking support
    var shouldTalking = false //是否只是掃描連線 or 跳到另一頁進行通訊
    var talkingPeripheral: CBPeripheral?
    var talkingCharacteristic: CBCharacteristic?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        if let split = self.splitViewController {
            let controllers = split.viewControllers
            self.detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }
        centralManager = CBCentralManager(delegate:self, queue: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if talkingPeripheral != nil {
            centralManager?.cancelPeripheralConnection(talkingPeripheral!)
            talkingPeripheral = nil
            talkingCharacteristic = nil
            
            // Resume the scan
            startToScan();
            
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        self.clearsSelectionOnViewWillAppear = self.splitViewController!.isCollapsed
        super.viewWillAppear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func insertNewObject(_ sender: Any) {
        objects.insert(NSDate(), at: 0)
        let indexPath = IndexPath(row: 0, section: 0)
        self.tableView.insertRows(at: [indexPath], with: .automatic)
    }

    // MARK: - Segues

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showDetail" {
            if self .tableView.indexPathForSelectedRow != nil {
                //let object = objects[indexPath.row] as! NSDate
                let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController
                //controller.detailItem = object
                controller.targetPeripheral = talkingPeripheral
                controller.targetCharacteristic  = talkingCharacteristic
                controller.navigationItem.leftBarButtonItem = self.splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
        } else if segue.identifier == "showSensorDetail" {
            let controller = segue.destination as! SensorDetailViewController
            controller.tartgetPeripheral = talkingPeripheral
            controller.targetCharacteristic  = talkingCharacteristic
        }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        return false;
    }

    // MARK: - Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return allItems.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        //here is called according whole rows
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        let allKeys = Array(allItems.keys)
        let targetKey = allKeys[indexPath.row]
        let targetItem = allItems[targetKey]
        let name = targetItem?.peripheral.name ?? "Unknow"
        cell.textLabel!.text = "\(name) RSSI: \(targetItem!.lastRSSI)"
        let lastScanSecondAgo = String(format: "%if", Date().timeIntervalSince(targetItem!.lastScanDateTime))
        cell.detailTextLabel!.text = "Last scan \(lastScanSecondAgo) seconds ago"
        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            objects.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        //detect one of lists is selected, and indexPath represent row index
        shouldTalking = true
        startToConnect(indexPath: indexPath)
    }
    
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        shouldTalking = false
        startToConnect(indexPath: indexPath)
    }
    
    func startToConnect(indexPath: IndexPath) {
        let allKeys = Array(allItems.keys)
        let targetKey = allKeys[indexPath.row]
        let targetItem = allItems[targetKey]
        
        NSLog("Connection to \(targetKey) ...")
        centralManager?.connect(targetItem!.peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "Unknown"
        NSLog("Connected to \(name)")
        
        stopToScan()
        
        // Try to discovery the services of peripheral
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        showAlert(msg: "Fail to connect!")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? "UnKnown"
        NSLog("Disconnected to \(name)")
        
        startToScan()
    }
    
    // Mark: CBPeripheralDElegate Methods
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // any error occurred then disconnect to peripheral
        if error != nil {
            centralManager?.cancelPeripheralConnection(peripheral)
            NSLog("Error: \(error)")
            return
        }
        
        // Prepare for collect detailInfo
        detailInfo = ""
        restServices.removeAll()
        
        // Prepare to discovery characterastic for each service
        restServices += peripheral.services!
        
        // Pick the first one
        let targetService = restServices.first
        restServices.remove(at: 0)
        peripheral.discoverCharacteristics(nil, for: targetService!)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            centralManager?.cancelPeripheralConnection(peripheral)
            NSLog("Error:\(error!)")
            return
        }
        
        detailInfo += "*** Peripheral: \(peripheral.name!) \(peripheral.services!.count) serices.\n"
        detailInfo += "** Service: \(service.uuid.uuidString) \(service.characteristics!.count) characteristics.\n"
        for tmp in service.characteristics! {
            detailInfo += "* Characteristics: \(tmp.uuid.uuidString)"
        
            // Check if shouldTalking is true and it is what are looking for.
            if shouldTalking && tmp.uuid.uuidString.lowercased() == target_characteristic_uuid {
                restServices.removeAll();
                talkingPeripheral = peripheral
                talkingCharacteristic = tmp
                // Link to Segue named showDetail
                self.performSegue(withIdentifier: "showDetail", sender: nil)
                return
            } else if shouldTalking && tmp.uuid.uuidString.lowercased() == sensor_characteristic_uuid {
                restServices.removeAll();
                talkingPeripheral = peripheral
                talkingCharacteristic = tmp
                // Link to Segue named showDetail
                self.performSegue(withIdentifier: "showSensorDetail", sender: nil)
                return
            }

        }
        // End of all discovering yet, or not
        if restServices.isEmpty {
    
            showAlert(msg: detailInfo)
            centralManager?.cancelPeripheralConnection(peripheral)
        } else {
            // Pick the first one
            let targetService = restServices.first
            restServices.remove(at: 0)
            peripheral.discoverCharacteristics(nil, for: targetService!)
        }
    }
    
    func startToScan()
    {
        NSLog("start scanning")
        let options = [CBCentralManagerScanOptionAllowDuplicatesKey:true]
        centralManager?.scanForPeripherals(withServices: nil, options: options)
    }
    
    func stopToScan()
    {
        centralManager?.stopScan()
    }
    
    func showAlert(msg: String) {
        // using UIAlertController to show alert msg
        let alert = UIAlertController(title: "", message: msg, preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "ok", style: UIAlertActionStyle.default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }

    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let status = central.state;
        if status != .poweredOn {
            //show Error Msg
            showAlert(msg: "BLE is not avaiable. (\(status.rawValue))");
        } else {
            startToScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let existItem = allItems[peripheral.identifier.uuidString]
        if existItem == nil {
            let name = (peripheral.name ?? "Unknown")
            NSLog("Discovered: \(name), RSSI: \(RSSI), UDID: \(peripheral.identifier.uuidString), AdvDate: \(advertisementData.description)")
        }
        let newItem = DiscoveredItem(newPeripheral: peripheral, RSSI: Int(RSSI))
        allItems[peripheral.identifier.uuidString] = newItem
        
        //Decide when to reload tableview
        let now = Date()
        if existItem == nil || lastReloadDate == nil || now.timeIntervalSince(lastReloadDate!) > 2.0 {
            lastReloadDate = now
            tableView.reloadData() // Refresh TableView
        }
    }
}

// define data structure for storing bluetooth device information
struct DiscoveredItem {
    var peripheral:CBPeripheral
    var lastRSSI:Int
    var lastScanDateTime:Date
    init(newPeripheral:CBPeripheral, RSSI:Int) {
        peripheral = newPeripheral
        lastRSSI = RSSI
        lastScanDateTime = Date()
    }
}

