//
//  FeedTableViewController.swift
//  hn-ios
//
//  Created by Pasha Pourmand on 7/19/18.
//  Copyright © 2018 Pasha Pourmand. All rights reserved.
//

import UIKit
import Alamofire

let baseUrlString = "https://hacker-news.firebaseio.com/v0/"

class HNApi: NSObject {

    static let sharedInstance = HNApi()
    
    private override init() {}

    public func fetchNews(size: Int, completionHandler: @escaping (Bool, [Story]) -> Void) {
        Alamofire.request(baseUrlString + "topstories.json").responseJSON { response in
            if var newStoriesJson = response.result.value as? NSArray {
                let numberOfStories = newStoriesJson.count > size ? size: newStoriesJson.count
                newStoriesJson = newStoriesJson.subarray(with: NSRange(location: 0, length: numberOfStories)) as NSArray
                
                var returnNews: [Story] = []
                let newsGroup = DispatchGroup()
                
                for (_, news) in newStoriesJson.enumerated() {
                    newsGroup.enter()
                    
                    Alamofire.request(baseUrlString + "item/\(news).json").responseJSON { response in
                        if let newsJSON = response.result.value as? NSDictionary {
                            let newsObject = Story.init(json: newsJSON)
                            returnNews.append(newsObject)
                        }
                        newsGroup.leave()
                    }
                }
                newsGroup.notify(queue: .main) {
                    returnNews.sort {a, b in
                        newStoriesJson.index(of: a.id!) < newStoriesJson.index(of: b.id!)
                    }
                    
                    completionHandler(true, returnNews)
                }
                
                
            }
            else {
                completionHandler(false, [])
            }
        }
    }
    
    public func grabComments(commentsIds: [Int], completionHandler: @escaping (Bool, [Comment]) -> Void) {
        var returnComments : [Comment] = []
        
        let commentsGroup = DispatchGroup()
        for commentId in commentsIds {
            commentsGroup.enter()
            
            Alamofire.request(baseUrlString + "item/\(commentId).json").responseJSON { response in
                if let commentJSON = response.result.value as? NSDictionary {
                    let commentObject = Comment.init(json: commentJSON)
                    commentObject.getComments(completionHandler: { (success) in
                        returnComments.append(commentObject)
                        commentsGroup.leave()
                    })
                } else {
                    commentsGroup.leave()
                }
            }
        }
        
        commentsGroup.notify(queue: .main) {
            returnComments.sort {a, b in
                commentsIds.index(of: a.id!)! < commentsIds.index(of: b.id!)!
            }
            
            completionHandler(true, returnComments)
        }
        
    }
}

class Story: NSObject {
    var id: Int?
    var title: String?
    var score: Int?
    var by: String?
    var url: URL?
    var time: Date?
    var commentsIds: NSArray = []
    var numberOfComments: Int? = 0
    
    convenience init(json: NSDictionary) {
        self.init()
        id = json.value(forKey: "id")    as? Int
        title = json.value(forKey: "title") as? String
        score = json.value(forKey: "score") as? Int
        by = json.value(forKey: "by")    as? String
        
        if let epochTime = json.value(forKey: "time") as? Int {
            time = Date(timeIntervalSince1970: TimeInterval(epochTime))
        }
        if let urlString = json.value(forKey: "url") as? String {
            url = URL(string: urlString)
        } else {
            url = URL(string: "https://news.ycombinator.com/item?id=" + String(describing: id!))
        }
        if let comments = json.value(forKey: "kids") as? NSArray {
            commentsIds = comments
            numberOfComments = comments.count
        }
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

class FeedTableViewController: UITableViewController {
    
    var allStories = [Story]()
    var selectedIndex = IndexPath()
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
        
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 85.0
        
        // refresh stuff
        let myRefreshControl = UIRefreshControl()
        myRefreshControl.addTarget(self, action:  #selector(refreshNewsFeed), for: UIControlEvents.valueChanged)
        self.refreshControl = myRefreshControl
        
        // Only on the initial load we want to animate this, otherwise
        // it will show up every time we refreshcontrol
        self.activityIndicator.startAnimating()

        refreshNewsFeed()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return allStories.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelCell", for: indexPath)
        
        let story = allStories[indexPath.row]
        
        // multilines!
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        
        let storyText:String = "\(story.title!)\n\n\(story.score!) points by \(story.by!) \(story.timeSincePosted()) | \(story.numberOfComments!) comments"
        
        cell.textLabel?.text = storyText
        
        // make our cells fun
        cell.backgroundColor = UIColor(red: 38, green: 38, blue: 38)
        cell.textLabel?.textColor = UIColor(red: 255, green: 255, blue: 255)
        
        // add a button to the cell
        let btn = UIButton()
        btn.backgroundColor = UIColor.green
        btn.setTitle("wtf", for: UIControlState.normal)
        btn.tag = indexPath.row

        cell.contentView.addSubview(btn)
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 120
    }
        
    @objc func refreshNewsFeed() {

        HNApi.sharedInstance.fetchNews(size: 100) { (success, news) in
            if (!success) {
                // TODO: put in behavior to nicely take care of error
                print("Wtf")
            }else {
                self.allStories = news
                self.activityIndicator.stopAnimating()
                self.tableView.reloadData()
                self.refreshControl?.endRefreshing()
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedIndex = indexPath
        performSegue(withIdentifier: "storySegue", sender: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if (segue.identifier == "storySegue") {
            let commentTableViewController = segue.destination as! CommentsTableViewController
            let story = allStories[selectedIndex.row]
            commentTableViewController.commentsIds = story.commentsIds as! [Int]
        }
    }
}

extension UIColor {
    convenience init(red: Int, green: Int, blue: Int) {
        let newRed = CGFloat(red)/255
        let newGreen = CGFloat(green)/255
        let newBlue = CGFloat(blue)/255
        
        self.init(red: newRed, green: newGreen, blue: newBlue, alpha: 1.0)
    }
}
