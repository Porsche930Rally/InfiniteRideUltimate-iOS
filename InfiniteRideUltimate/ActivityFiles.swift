import Foundation
import CoreLocation

enum ActivityImporter {
    static func load(_ url: URL) throws -> RideActivity {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url), ext = url.pathExtension.lowercased()
        if ext == "gpx" || ext == "tcx" || ext == "xml" { return try XMLActivityParser.parse(data, name: url.deletingPathExtension().lastPathComponent) }
        if ext == "fit" { return try FITActivityParser.parse(data, name: url.deletingPathExtension().lastPathComponent) }
        if ext == "csv" { return try parseCSV(data, name: url.deletingPathExtension().lastPathComponent) }
        throw NSError(domain:"InfiniteRideImport",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose a FIT, GPX, TCX or InfiniteRide CSV file."])
    }

    private static func parseCSV(_ data: Data, name: String) throws -> RideActivity {
        guard let text=String(data:data,encoding:.utf8) else { throw NSError(domain:"InfiniteRideImport",code:2,userInfo:[NSLocalizedDescriptionKey:"The CSV file is not valid UTF-8 text."]) }
        let lines=text.split(whereSeparator:\.isNewline);guard let header=lines.first else{throw NSError(domain:"InfiniteRideImport",code:3,userInfo:[NSLocalizedDescriptionKey:"The CSV file is empty."])}
        let keys=header.split(separator:",").map{String($0).lowercased()};func index(_ names:[String])->Int?{keys.firstIndex{names.contains($0)}}
        let ti=index(["elapsed_s","elapsed","time"]),di=index(["distance_m","distance"]),si=index(["speed_mps","speed"]),hi=index(["heart_rate","hr"]),ci=index(["cadence"]),pi=index(["power","watts"]),lai=index(["latitude","lat"]),loi=index(["longitude","lon"]),ai=index(["altitude_m","altitude"])
        var rows:[RideSample]=[];for line in lines.dropFirst(){let v=line.split(separator:",",omittingEmptySubsequences:false).map(String.init);func d(_ i:Int?)->Double{guard let i,i<v.count else{return 0};return Double(v[i]) ?? 0};let lat=d(lai),lon=d(loi);rows.append(RideSample(date:Date().addingTimeInterval(d(ti)),elapsed:d(ti),distanceMeters:d(di),speedMps:d(si),heartRate:Int(d(hi)),cadence:Int(d(ci)),power:Int(d(pi)),altitudeMeters:d(ai),grade:0,coordinate:lat==0&&lon==0 ? nil:Coordinate(.init(latitude:lat,longitude:lon)),powerMeasured:d(pi)>0))}
        return build(rows,name:name)
    }

    static func build(_ input:[RideSample],name:String)->RideActivity{var rows=input.sorted{$0.elapsed<$1.elapsed},distance=0.0;for i in rows.indices{if i>0&&rows[i].distanceMeters<=0{let dt=max(0,rows[i].elapsed-rows[i-1].elapsed);let before=distance;if let a=rows[i-1].coordinate?.cl,let b=rows[i].coordinate?.cl{distance += CLLocation(latitude:a.latitude,longitude:a.longitude).distance(from:CLLocation(latitude:b.latitude,longitude:b.longitude))}else{distance += rows[i].speedMps*dt};rows[i].distanceMeters=distance;if rows[i].speedMps<=0&&dt>0{rows[i].speedMps=(distance-before)/dt};let run=distance-before;if run>2{rows[i].grade=min(0.25,max(-0.25,(rows[i].altitudeMeters-rows[i-1].altitudeMeters)/run))}}else{distance=max(distance,rows[i].distanceMeters)}};let start=rows.first?.date ?? Date(),duration=rows.last?.elapsed ?? 0;return RideActivity(startedAt:start,kind:.solo,duration:duration,distanceMeters:distance,samples:rows,routeName:name)}
}

private final class XMLActivityParser: NSObject, XMLParserDelegate {
    private var rows:[RideSample]=[],current="",text="",stack:[String]=[],lat=0.0,lon=0.0,alt=0.0,hr=0,cad=0,power=0,speed=0.0,distance=0.0,time:Date?,firstTime:Date?
    private var inPoint=false
    static func parse(_ data:Data,name:String)throws->RideActivity{let delegate=XMLActivityParser(),parser=XMLParser(data:data);parser.delegate=delegate;guard parser.parse() else{throw parser.parserError ?? NSError(domain:"InfiniteRideImport",code:4,userInfo:[NSLocalizedDescriptionKey:"The GPX or TCX file could not be parsed."])};return ActivityImporter.build(delegate.rows,name:name)}
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName qName:String?,attributes:[String:String]=[:]){current=elementName.lowercased();stack.append(current);text="";if current=="trkpt"||current=="trackpoint"{inPoint=true;lat=Double(attributes["lat"] ?? "") ?? 0;lon=Double(attributes["lon"] ?? "") ?? 0;alt=0;hr=0;cad=0;power=0;speed=0;distance=0;time=nil}}
    func parser(_ parser:XMLParser,foundCharacters string:String){text+=string}
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName qName:String?){let e=elementName.lowercased(),value=text.trimmingCharacters(in:.whitespacesAndNewlines);if inPoint{if e=="latitudedegrees"{lat=Double(value) ?? lat}else if e=="longitudedegrees"{lon=Double(value) ?? lon}else if e=="ele"||e=="altitudemeters"{alt=Double(value) ?? 0}else if e=="time"{time=ISO8601DateFormatter().date(from:value)}else if e=="value"&&stack.contains("heartratebpm")||e=="hr"{hr=Int(value) ?? hr}else if e=="cadence"{cad=Int(value) ?? 0}else if e=="watts"||e=="power"{power=Int(value) ?? 0}else if e=="speed"{speed=Double(value) ?? 0}else if e=="distancemeters"{distance=Double(value) ?? 0}else if e=="trkpt"||e=="trackpoint"{let stamp=time ?? Date().addingTimeInterval(Double(rows.count));if firstTime==nil{firstTime=stamp};let elapsed=stamp.timeIntervalSince(firstTime!);let coordinate=lat==0&&lon==0 ? nil:Coordinate(.init(latitude:lat,longitude:lon));rows.append(RideSample(date:stamp,elapsed:max(0,elapsed),distanceMeters:distance,speedMps:speed,heartRate:hr,cadence:cad,power:power,altitudeMeters:alt,grade:0,coordinate:coordinate,powerMeasured:power>0));inPoint=false}};if !stack.isEmpty{stack.removeLast()};current=stack.last ?? "";text=""}
}

private enum FITActivityParser {
    struct Field {var number:Int;var size:Int;var type:Int}
    struct Definition {var global:Int;var bigEndian:Bool;var fields:[Field]}
    static func parse(_ data: Data, name: String) throws -> RideActivity {
        let bytes = [UInt8](data)
        guard bytes.count >= 14, bytes[8] == 46, bytes[9] == 70, bytes[10] == 73, bytes[11] == 84 else {
            throw NSError(domain: "InfiniteRideFIT", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid FIT header"])
        }
        let headerSize = Int(bytes[0])
        guard headerSize >= 12, headerSize < bytes.count else {
            throw NSError(domain: "InfiniteRideFIT", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid FIT header size"])
        }
        let dataSize = Int(u32(bytes, 4, false))
        let end = min(bytes.count, headerSize + dataSize)
        let fitEpoch = Date(timeIntervalSince1970: 631065600)
        var index = headerSize
        var definitions: [Int: Definition] = [:]
        var rows: [RideSample] = []
        var lastTimestamp: UInt32 = 0

        while index < end {
            let header = bytes[index]
            index += 1
            let compressed = (header & 0x80) != 0
            let definitionMessage = !compressed && (header & 0x40) != 0
            if definitionMessage {
                let local = Int(header & 0x0F)
                let hasDeveloperFields = (header & 0x20) != 0
                guard index + 5 <= end else { break }
                index += 1
                let bigEndian = bytes[index] != 0
                index += 1
                let global = Int(u16(bytes, index, bigEndian))
                index += 2
                let count = Int(bytes[index])
                index += 1
                var fields: [Field] = []
                for _ in 0..<count {
                    guard index + 3 <= end else { break }
                    fields.append(Field(number: Int(bytes[index]), size: Int(bytes[index + 1]), type: Int(bytes[index + 2])))
                    index += 3
                }
                if hasDeveloperFields, index < end {
                    let developerCount = Int(bytes[index])
                    index = min(end, index + 1 + developerCount * 3)
                }
                definitions[local] = Definition(global: global, bigEndian: bigEndian, fields: fields)
                continue
            }

            let local = compressed ? Int((header >> 5) & 0x03) : Int(header & 0x0F)
            guard let definition = definitions[local] else { break }
            var values: [Int: UInt64] = [:]
            for field in definition.fields {
                guard index + field.size <= end else { index = end; break }
                values[field.number] = read(bytes, index, field.size, definition.bigEndian)
                index += field.size
            }
            guard definition.global == 20 else { continue }

            var timestamp = UInt32(values[253] ?? UInt64(lastTimestamp))
            if compressed {
                let offset = UInt32(header & 0x1F)
                timestamp = (lastTimestamp & ~UInt32(0x1F)) | offset
                if timestamp < lastTimestamp { timestamp += 0x20 }
            }
            lastTimestamp = timestamp
            let latitude = semicircle(values[0])
            let longitude = semicircle(values[1])
            let enhancedAltitude = values[78].map { Double($0) / 5.0 - 500.0 }
            let standardAltitude = values[2].map { Double($0) / 5.0 - 500.0 }
            let altitude = enhancedAltitude ?? standardAltitude ?? 0.0
            let enhancedSpeed = values[73].map { Double($0) / 1000.0 }
            let standardSpeed = values[6].map { Double($0) / 1000.0 }
            let speed = enhancedSpeed ?? standardSpeed ?? 0.0
            let date = fitEpoch.addingTimeInterval(Double(timestamp))
            let elapsed = rows.isEmpty ? 0 : date.timeIntervalSince(rows[0].date)
            let coordinate: Coordinate?
            if let latitude, let longitude { coordinate = Coordinate(.init(latitude: latitude, longitude: longitude)) }
            else { coordinate = nil }
            let distance = Double(values[5] ?? 0) / 100.0
            let heartRate = Int(values[3] ?? 0)
            let cadence = Int(values[4] ?? 0)
            let power = Int(values[7] ?? 0)
            let sample = RideSample(
                date: date,
                elapsed: max(0.0, elapsed),
                distanceMeters: distance,
                speedMps: speed,
                heartRate: heartRate,
                cadence: cadence,
                power: power,
                altitudeMeters: altitude,
                grade: 0.0,
                coordinate: coordinate,
                powerMeasured: power > 0
            )
            rows.append(sample)
        }
        guard !rows.isEmpty else {
            throw NSError(domain: "InfiniteRideFIT", code: 2, userInfo: [NSLocalizedDescriptionKey: "No cycling records found in FIT file"])
        }
        return ActivityImporter.build(rows, name: name)
    }
    static func u16(_ b:[UInt8],_ i:Int,_ big:Bool)->UInt16{big ? UInt16(b[i])<<8|UInt16(b[i+1]):UInt16(b[i])|UInt16(b[i+1])<<8}
    static func u32(_ b:[UInt8],_ i:Int,_ big:Bool)->UInt32{var v:UInt32=0;if big{for x in 0..<4{v=(v<<8)|UInt32(b[i+x])}}else{for x in 0..<4{v|=UInt32(b[i+x])<<UInt32(8*x)}};return v}
    static func read(_ b:[UInt8],_ i:Int,_ size:Int,_ big:Bool)->UInt64{var v:UInt64=0;if big{for x in 0..<min(size,8){v=(v<<8)|UInt64(b[i+x])}}else{for x in 0..<min(size,8){v|=UInt64(b[i+x])<<UInt64(8*x)}};return v}
    static func semicircle(_ value:UInt64?)->Double?{guard let value else{return nil};let signed=Int32(bitPattern:UInt32(value));if signed==Int32.max{return nil};return Double(signed)*180/2147483648}
}

enum ActivityExporter {
    static func csv(_ ride:RideActivity)throws->URL{var text="elapsed_s,distance_m,speed_mps,heart_rate,cadence,power,altitude_m,grade,latitude,longitude,power_measured\n";for s in ride.samples{text+=String(format:"%0.1f,%0.2f,%0.3f,%d,%d,%d,%0.2f,%0.5f,%0.7f,%0.7f,%@\n",s.elapsed,s.distanceMeters,s.speedMps,s.heartRate,s.cadence,s.power,s.altitudeMeters,s.grade,s.coordinate?.latitude ?? 0,s.coordinate?.longitude ?? 0,s.powerMeasured ? "true":"false")};let url=temp("InfiniteRide-\(ride.id.uuidString).csv");try text.data(using:.utf8)!.write(to:url);return url}
    static func gpx(_ ride:RideActivity)throws->URL{let iso=ISO8601DateFormatter();var text="<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"InfiniteRide by INfiniteBoost45\"><trk><name>InfiniteRide</name><trkseg>";for s in ride.samples{if let c=s.coordinate{text+="<trkpt lat=\"\(c.latitude)\" lon=\"\(c.longitude)\"><ele>\(s.altitudeMeters)</ele><time>\(iso.string(from:s.date))</time></trkpt>"}};text+="</trkseg></trk></gpx>";let url=temp("InfiniteRide-\(ride.id.uuidString).gpx");try text.data(using:.utf8)!.write(to:url);return url}
    private static func temp(_ name:String)->URL{FileManager.default.temporaryDirectory.appendingPathComponent(name)}
}
