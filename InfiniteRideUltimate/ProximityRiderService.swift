import Foundation
import CoreBluetooth
import CoreLocation

struct NearbyPeer: Identifiable, Hashable {
    var id: UUID
    var name: String
    var heartRate: Int
    var cadence: Int
    var power: Int
    var speedMps: Double
    var coordinate: Coordinate?
    var role: TeamRole
    var rssi: Int
    var updatedAt: Date
}

final class ProximityRiderService: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {
    @Published var peers:[NearbyPeer]=[]
    @Published var active=false
    @Published var status="Rider sharing off"
    private var central:CBCentralManager!,peripheralManager:CBPeripheralManager!,characteristic:CBMutableCharacteristic?
    private var peripherals:[UUID:CBPeripheral]=[:]
    private let serviceID=CBUUID(string:"D87A0001-45B0-4D0B-A775-494E46524944"),valueID=CBUUID(string:"D87A0002-45B0-4D0B-A775-494E46524944")
    private var localPayload=Data("{}".utf8),localName="Rider"

    override init(){super.init();central=CBCentralManager(delegate:self,queue:.main);peripheralManager=CBPeripheralManager(delegate:self,queue:.main)}

    func start(name:String){localName=String(name.prefix(20));active=true;if central.state == .poweredOn{central.scanForPeripherals(withServices:[serviceID],options:[CBCentralManagerScanOptionAllowDuplicatesKey:true])};beginAdvertising();status="Finding nearby InfiniteRide phones"}
    func stop(){active=false;central.stopScan();peripheralManager.stopAdvertising();status="Rider sharing off"}
    func update(name:String,role:TeamRole,heart:Int,cadence:Int,power:Int,speed:Double,location:CLLocation?){localName=String(name.prefix(20));let packet:RiderPacket = .init(name:localName,role:role.rawValue,heart:heart,cadence:cadence,power:power,speed:speed,lat:location?.coordinate.latitude,lon:location?.coordinate.longitude);if let data=try? JSONEncoder().encode(packet){localPayload=data;if let characteristic{_ = peripheralManager.updateValue(data,for:characteristic,onSubscribedCentrals:nil)}}}

    func centralManagerDidUpdateState(_ central:CBCentralManager){if central.state == .poweredOn&&active{central.scanForPeripherals(withServices:[serviceID],options:[CBCentralManagerScanOptionAllowDuplicatesKey:true])}}
    func peripheralManagerDidUpdateState(_ peripheral:CBPeripheralManager){if peripheral.state == .poweredOn&&active{installService();beginAdvertising()}}
    private func installService(){guard characteristic==nil else{return};let c=CBMutableCharacteristic(type:valueID,properties:[.read,.notify],value:nil,permissions:[.readable]);let s=CBMutableService(type:serviceID,primary:true);s.characteristics=[c];characteristic=c;peripheralManager.add(s)}
    private func beginAdvertising(){guard active,peripheralManager.state == .poweredOn else{return};installService();peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey:[serviceID],CBAdvertisementDataLocalNameKey:localName])}
    func peripheralManager(_ peripheral:CBPeripheralManager,didReceiveRead request:CBATTRequest){guard request.characteristic.uuid==valueID else{peripheral.respond(to:request,withResult:.requestNotSupported);return};request.value=localPayload;peripheral.respond(to:request,withResult:.success)}

    func centralManager(_ central:CBCentralManager,didDiscover peripheral:CBPeripheral,advertisementData:[String:Any],rssi RSSI:NSNumber){peripherals[peripheral.identifier]=peripheral;let advertised=advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "InfiniteRide rider";upsert(id:peripheral.identifier,name:advertised,rssi:RSSI.intValue);if peripheral.state == .disconnected{central.connect(peripheral)}}
    func centralManager(_ central:CBCentralManager,didConnect peripheral:CBPeripheral){peripheral.delegate=self;peripheral.discoverServices([serviceID])}
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?){if active{central.connect(peripheral)}}
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?){peripheral.services?.forEach{peripheral.discoverCharacteristics([valueID],for:$0)}}
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?){for c in service.characteristics ?? [] where c.uuid==valueID{peripheral.readValue(for:c);peripheral.setNotifyValue(true,for:c)}}
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?){guard let data=characteristic.value,let packet=try? JSONDecoder().decode(RiderPacket.self,from:data)else{return};let coordinate:Coordinate? = packet.lat != nil&&packet.lon != nil ? Coordinate(.init(latitude:packet.lat!,longitude:packet.lon!)):nil;let peer=NearbyPeer(id:peripheral.identifier,name:packet.name,heartRate:packet.heart,cadence:packet.cadence,power:packet.power,speedMps:packet.speed,coordinate:coordinate,role:TeamRole(rawValue:packet.role) ?? .support,rssi:peers.first(where:{$0.id==peripheral.identifier})?.rssi ?? -80,updatedAt:Date());if let i=peers.firstIndex(where:{$0.id==peer.id}){peers[i]=peer}else{peers.append(peer)}}
    private func upsert(id:UUID,name:String,rssi:Int){if let i=peers.firstIndex(where:{$0.id==id}){peers[i].rssi=rssi;peers[i].updatedAt=Date()}else{peers.append(.init(id:id,name:name,heartRate:0,cadence:0,power:0,speedMps:0,coordinate:nil,role:.support,rssi:rssi,updatedAt:Date()))}}

    func localPosition(location:CLLocation?,heading:Double,teamIDs:Set<UUID>)->(position:Int,total:Int,spread:Double){guard let location else{return(1,1,0)};var rows:[Double]=[0];for p in peers where teamIDs.contains(p.id){if let c=p.coordinate{let target=CLLocation(latitude:c.latitude,longitude:c.longitude),distance=location.distance(from:target),bearing=bearing(location.coordinate,c.cl),along=distance*cos((bearing-heading)*Double.pi/180);rows.append(along)}};let sorted=rows.sorted(by:>),position=(sorted.firstIndex(where:{abs($0)<0.001}) ?? 0)+1;return(position,rows.count,(sorted.first ?? 0)-(sorted.last ?? 0))}
    private func bearing(_ a:CLLocationCoordinate2D,_ b:CLLocationCoordinate2D)->Double{let p1=a.latitude*Double.pi/180,p2=b.latitude*Double.pi/180,dl=(b.longitude-a.longitude)*Double.pi/180;return atan2(sin(dl)*cos(p2),cos(p1)*sin(p2)-sin(p1)*cos(p2)*cos(dl))*180/Double.pi}
    private struct RiderPacket:Codable{var name:String,role:String;var heart:Int,cadence:Int,power:Int;var speed:Double;var lat:Double?,lon:Double?}
}
