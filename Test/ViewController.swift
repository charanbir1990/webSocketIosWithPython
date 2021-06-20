//
//  ViewController.swift
//  Test
//
//  Created by charanbir sandhu on 20/06/21.
//

import UIKit

class ViewController: UIViewController, WebSocketConnectionDelegate {
    @IBOutlet weak var img: UIImageView!
    
    var frame: FrameExtractor?
    
    var webSocketConnection: WebSocketConnection!
    
    var isConnected = false
    
    @IBAction func click(_ sender: UIButton) {
        frame?.flipCamera()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        frame = FrameExtractor()
        frame?.delegate = self
        webSocketConnection = WebSocketTaskConnection(url: URL(string: "ws://192.168.0.103:8000")!)
        webSocketConnection.delegate = self
        
        webSocketConnection.connect()
        
//        webSocketConnection.send(text: "ping")
    }
    
    func onConnected(connection: WebSocketConnection) {
        print("Connected")
        isConnected = true
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            guard let data = self.img.image?.jpegData(compressionQuality: 0.1) else {return}
            self.webSocketConnection.send(data: data)
        }
//        DispatchQueue.global().async {
//            var count: Int = 0
//            while true {
//                count += 1
//                var file = "1"
//                if count % 2 == 0 {
//                    file = "2"
//                }
//                guard let url = Bundle.main.url(forResource: file, withExtension: ".png") else {return}
//                let image = UIImage(contentsOfFile: url.path)
//                DispatchQueue.main.async {
//                    self.img.image = image
//                    guard let data = image?.pngData() else {return}
//                    webSocketConnection.send(data: data)
//                }
//
//                sleep(1)
//            }
//        }
        
    }
    
    func onDisconnected(connection: WebSocketConnection, error: Error?) {
        isConnected = false
        if let error = error {
            print("Disconnected with error:\(error)")
        } else {
            print("Disconnected normally")
        }
    }
    
    func onError(connection: WebSocketConnection, error: Error) {
        print("Connection error:\(error)")
    }
    
    func onMessage(connection: WebSocketConnection, text: String) {
        print("Text message: \(text)")
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//            self.webSocketConnection.send(text: "ping")
//        }
    }
    
    func onMessage(connection: WebSocketConnection, data: Data) {
        DispatchQueue.main.async {
            if self.isConnected {
                guard let data = self.img.image?.jpegData(compressionQuality: 0.3) else {return}
                self.webSocketConnection.send(data: data)
            }
        }
//        print("Data message: \(data)")
//        let image = UIImage(data: data)
//        DispatchQueue.main.async {
//            self.img.image = image
//        }
    }

}

extension ViewController: FrameExtractorDelegate {
    func recorderCanSetFilter(image: CIImage) -> CIImage {
        return image
    }
    
    func recorderDidUpdate(image: UIImage) {
        DispatchQueue.main.async {
            self.img.image = image
        }
    }
    
    func recorderDidStartRecording() {
        
    }
    
    func recorderDidAbortRecording() {
        
    }
    
    func recorderDidFinishRecording() {
        
    }
    
    func recorderWillStartWriting() {
        
    }
    
    func recorderDidFinishWriting(outputURL: URL) {
        
    }
    
    func recorderDidFail(error: LocalizedError) {
        
    }
    
    
}
