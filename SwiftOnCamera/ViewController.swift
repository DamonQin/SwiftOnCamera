//
//  ViewController.swift
//  SwiftOnCamera
//
//  Created by QinChong on 15/3/11.
//  Copyright (c) 2015年 Damon Qin. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    var cameraViewController: SOController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "camera" {
            cameraViewController = segue.destinationViewController as? SOController
        }
    }

    @IBAction func captureImage(sender: UIButton) {
        cameraViewController?.snapStillImage()
    }
}

