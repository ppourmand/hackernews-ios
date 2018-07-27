//
//  CommentsTableViewController.swift
//  hn-ios
//
//  Created by Pasha Pourmand on 7/24/18.
//  Copyright © 2018 Pasha Pourmand. All rights reserved.
//
import Alamofire
import UIKit

class Comment {
    var id: Int?
    var by: String?
    var text: String?
    var time: Date?
    var deleted: Bool?
    var childCommentIds: [Int] = []
    var childComments: [Comment] = []
    var indentLevel: Int = 0
    
    convenience init(json: NSDictionary) {
        self.init()
        id = json.value(forKey: "id") as? Int
        by = json.value(forKey: "by") as? String
        text = json.value(forKey: "text") as? String
        deleted = json.value(forKey: "deleted") as? Bool
        
        if let epochTime = json.value(forKey: "time") as? Int {
            time = Date(timeIntervalSince1970: TimeInterval(epochTime))
        }
        
        if let childCommentIdsJSON = json.value(forKey: "kids") as? [Int] {
            childCommentIds = childCommentIdsJSON
        }
    }
    
    func getComments(completionHandler: @escaping (Bool) -> Void) {
        if childCommentIds.count > 0 {
            var commentsReturned = [Comment]()
            let commentGroup = DispatchGroup()
            
            for commentId in childCommentIds {
                commentGroup.enter()
                let currentIndentLevel = self.indentLevel
                
                Alamofire.request(baseUrlString + "item/\(commentId).json").responseJSON { reponse in
                    if let commentJSON = reponse.result.value as? NSDictionary {
                        let commentObject = Comment.init(json: commentJSON)
                        commentObject.indentLevel = currentIndentLevel + 1
                        commentObject.getComments(completionHandler: { (success) in
                            commentsReturned.append(commentObject)
                            commentGroup.leave()
                        })
                    }
                    else {
                        commentGroup.leave()
                    }
                }
            }
            commentGroup.notify(queue: .main) {
                self.childComments = commentsReturned
                completionHandler(true)
            }
        }
        else
        {
            completionHandler(true)
        }
    }
    
    func flattenedComments() -> Any {
        var commentsArray: [Any] = [self]
        for comment in childComments {
            commentsArray += comment.flattenedComments() as! Array<Any>
        }
        return commentsArray
    }
    
    func timeSincePosted() -> String {
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: self.time!, to: Date())
        
        //        print("days: \(components.day!) hours: \(components.hour!) minutes: \(components.minute!)")
        
        if (components.hour! == 0) {
            return "\(components.minute!) minutes ago"
        }
        else if (components.hour! == 1) {
            return "\(components.hour!) hour ago"
        }
        else if (components.hour! > 23 && components.hour! < 49) {
            return "\(components.day!) day ago"
        }
        else if (components.day! > 48) {
            return "\(components.day!) days ago"
        }
        return "\(components.hour!) hours ago"
    }
    
}

class CommentsTableViewController: UITableViewController {
    var commentsIds : [Int] = []
    var flatennedComments : [Comment] = []
    let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // no empty cells on load cuz its ugly
        tableView.tableFooterView = UIView(frame: .zero)
        
        // from https://stackoverflow.com/a/45700623
        tableView.addSubview(self.activityIndicator)
        self.activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        self.activityIndicator.hidesWhenStopped = true
        self.activityIndicator.color = UIColor.white
        let horizontalConstraint = NSLayoutConstraint(item: self.activityIndicator, attribute: NSLayoutAttribute.centerX, relatedBy: NSLayoutRelation.equal, toItem: tableView, attribute: NSLayoutAttribute.centerX, multiplier: 1, constant: 0)
        tableView.addConstraint(horizontalConstraint)
        let verticalConstraint = NSLayoutConstraint(item: self.activityIndicator, attribute: NSLayoutAttribute.centerY, relatedBy: NSLayoutRelation.equal, toItem: tableView, attribute: NSLayoutAttribute.centerY, multiplier: 1, constant: 0)
        tableView.addConstraint(verticalConstraint)
        
        // Set automatic height calculation for cells
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 85.0
        
        // Start refresh when view is loaded
        tableView.setContentOffset(CGPoint(x: 0, y: tableView.contentOffset.y - 30), animated: false)
        
        // refresh stuff
        let myRefreshControl = UIRefreshControl()
        myRefreshControl.addTarget(self, action:  #selector(refreshComments), for: UIControlEvents.valueChanged)
        self.refreshControl = myRefreshControl
        
        self.activityIndicator.startAnimating()
        refreshComments()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.flatennedComments.count
    }
    
    @objc func refreshComments() {
        HNApi.sharedInstance.grabComments(commentsIds: commentsIds ) { (success, comments) in
            // Update array of news and interface
            var flattenComments = [Any]()
            for comment in comments {
                flattenComments += comment.flattenedComments() as! Array<Any>
            }
            self.flatennedComments = flattenComments.compactMap { $0 } as! [Comment]
            self.activityIndicator.stopAnimating()
            self.tableView.reloadData()
            self.refreshControl?.endRefreshing()
            
            if (!success) {
                print("issue with grabbing comments")
            }
            
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Comment Cell", for: indexPath)

        let comment = flatennedComments[indexPath.row]
        var totalText: String = ""
        
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        
        // post text html crap
        if comment.by != nil || comment.text != nil{
            totalText = "\(comment.by!) \(comment.timeSincePosted())</br></br>\(comment.text!)"
        }
        else {
            totalText = "[deleted] \(comment.timeSincePosted())</br></br>[deleted]"
        }
        cell.textLabel?.attributedText = totalText.htmlAttributed(family: "Helvetica", size: 12.0, color: #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        
        // make our cells fun
        cell.backgroundColor = UIColor(red: 38, green: 38, blue: 38)
        cell.textLabel?.textColor = UIColor(red: 255, green: 255, blue: 255)
        
        // indentation stuff
        cell.indentationLevel = comment.indentLevel
        cell.indentationWidth = 20

        return cell
    }

}

// Everything below this comment is from:
// https://medium.com/@valv0/a-swift-extension-for-string-and-html-8cfb7477a510
extension UIColor {
    var hexString:String? {
        if let components = self.cgColor.components {
            let r = components[0]
            let g = components[1]
            let b = components[2]
            return  String(format: "%02X%02X%02X", (Int)(r * 255), (Int)(g * 255), (Int)(b * 255))
        }
        return nil
    }
}

extension String {
    var html2Attributed: NSAttributedString? {
        do {
            guard let data = data(using: String.Encoding.utf8) else {
                return nil
            }
            return try NSAttributedString(data: data,
                                          options: [.documentType: NSAttributedString.DocumentType.html,
                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                          documentAttributes: nil)
        } catch {
            print("error: ", error)
            return nil
        }
    }
    
    var htmlAttributed: (NSAttributedString?, NSDictionary?) {
        do {
            guard let data = data(using: String.Encoding.utf8) else {
                return (nil, nil)
            }
            
            var dict:NSDictionary?
            dict = NSMutableDictionary()
            
            return try (NSAttributedString(data: data,
                                           options: [.documentType: NSAttributedString.DocumentType.html,
                                                     .characterEncoding: String.Encoding.utf8.rawValue],
                                           documentAttributes: &dict), dict)
        } catch {
            print("error: ", error)
            return (nil, nil)
        }
    }
    
    func htmlAttributed(using font: UIFont, color: UIColor) -> NSAttributedString? {
        do {
            let htmlCSSString = "<style>" +
                "html *" +
                "{" +
                "font-size: \(font.pointSize)pt !important;" +
                "color: #\(color.hexString!) !important;" +
                "font-family: \(font.familyName), Helvetica !important;" +
            "}</style> \(self)"
            
            guard let data = htmlCSSString.data(using: String.Encoding.utf8) else {
                return nil
            }
            
            return try NSAttributedString(data: data,
                                          options: [.documentType: NSAttributedString.DocumentType.html,
                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                          documentAttributes: nil)
        } catch {
            print("error: ", error)
            return nil
        }
    }
    
    func htmlAttributed(family: String?, size: CGFloat, color: UIColor) -> NSAttributedString? {
        do {
            let htmlCSSString = "<style>" +
                "html *" +
                "{" +
                "font-size: \(size)pt !important;" +
                "color: #\(color.hexString!) !important;" +
                "font-family: \(family ?? "Helvetica"), Helvetica !important;" +
            "}</style> \(self)"
            
            guard let data = htmlCSSString.data(using: String.Encoding.utf8) else {
                return nil
            }
            
            return try NSAttributedString(data: data,
                                          options: [.documentType: NSAttributedString.DocumentType.html,
                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                          documentAttributes: nil)
        } catch {
            print("error: ", error)
            return nil
        }
    }
}
