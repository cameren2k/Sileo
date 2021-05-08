//
//  FeaturedViewController.swift
//  Sileo
//
//  Created by CoolStar on 8/18/19.
//  Copyright © 2019 CoolStar. All rights reserved.
//

import Foundation

class FeaturedViewController: SileoViewController, UIScrollViewDelegate, FeaturedViewDelegate {
    private var profileButton: UIButton?
    @IBOutlet var scrollView: UIScrollView?
    @IBOutlet var activityIndicatorView: UIActivityIndicatorView?
    var featuredView: FeaturedBaseView?
    var cachedData: [String: Any]?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = String(localizationKey: "Featured_Page")
        
        self.setupProfileButton()
        
        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(updatePicture),
                                               name: Notification.Name("iCloudProfile"),
                                               object: nil)
        
        UIView.animate(withDuration: 0.7, animations: {
            self.activityIndicatorView?.alpha = 0
        }, completion: { _ in
            self.activityIndicatorView?.isHidden = true
        })
        DispatchQueue.global(qos: .userInitiated).async {
            PackageListManager.shared.waitForReady()
        }
        
        #if targetEnvironment(simulator) || TARGET_SANDBOX
        #else
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + .milliseconds(500)) {
            let (status, output, _) = spawnAsRoot(args: ["/usr/bin/whoami"])
            if status != 0 || output != "root\n" {
                DispatchQueue.main.sync {
                    let alertController = UIAlertController(title: String(localizationKey: "Installation_Error.Title", type: .error),
                                                            message: String(localizationKey: "Installation_Error.Body", type: .error),
                                                            preferredStyle: .alert)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
            
            PackageListManager.shared.waitForReady()
            
            var foundBroken = false
            
            if let installedPackages = PackageListManager.shared.packagesList(loadIdentifier: "--installed", repoContext: nil) {
                for package in installedPackages where package.status == .halfconfigured {
                    foundBroken = true
                }
            }
            
            if DpkgWrapper.dpkgInterrupted() || foundBroken {
                DispatchQueue.main.sync {
                    let alertController = UIAlertController(title: String(localizationKey: "FixingDpkg.Title", type: .error),
                                                            message: String(localizationKey: "FixingDpkg.Body", type: .error),
                                                            preferredStyle: .alert)
                    self.present(alertController, animated: true, completion: nil)
                }
                
                DispatchQueue.global(qos: .default).async {
                    let (status, output, errorOutput) = spawnAsRoot(args: ["/usr/bin/dpkg", "--configure", "-a"])
                    
                    PackageListManager.shared.purgeCache()
                    PackageListManager.shared.waitForReady()
                    
                    DispatchQueue.main.async {
                        self.dismiss(animated: true) {
                            if status != 0 {
                                let errorAttrs = [NSAttributedString.Key.foregroundColor: Dusk.errorColor]
                                let errorString = NSMutableAttributedString(string: errorOutput, attributes: errorAttrs)
                                
                                let stringAttrs = [NSAttributedString.Key.foregroundColor: Dusk.foregroundColor]
                                let mutableAttributedString = NSMutableAttributedString(string: output, attributes: stringAttrs)
                                mutableAttributedString.append(NSAttributedString(string: "\n"))
                                mutableAttributedString.append(errorString)
                                
                                let errorsVC = SourcesErrorsViewController(nibName: "SourcesErrorsViewController", bundle: nil)
                                errorsVC.attributedString = mutableAttributedString
                                
                                let navController = UINavigationController(rootViewController: errorsVC)
                                navController.navigationBar.barStyle = .blackTranslucent
                                navController.modalPresentationStyle = .formSheet
                                self.present(navController, animated: true, completion: nil)
                            }
                        }
                    }
                }
            }
        }
        #endif
    }
    
    private var userAgent: String {
        let cfVersion = String(format: "%.3f", kCFCoreFoundationVersionNumber)
        let bundleName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] ?? ""
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? ""
        let osType = UIDevice.current.kernOSType
        let osRelease = UIDevice.current.kernOSRelease
        return "\(bundleName)/\(bundleVersion)/FeaturedPage CoreFoundation/\(cfVersion) \(osType)/\(osRelease)"
    }
    
    @objc func reloadData() {
        if UIApplication.shared.applicationState == .background {
            return
        }
        let deviceName = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        guard let jsonURL = StoreURL("featured-\(deviceName).json") else {
            return
        }
        let agent = self.userAgent 
        let headers: [String: String] = ["User-Agent": agent]
        AmyNetworkResolver.dict(url: jsonURL, headers: headers, cache: true) { success, dict in
            guard success,
                  let dict = dict else { return }
            if let cachedData = self.cachedData,
               NSDictionary(dictionary: cachedData).isEqual(to: dict) {
                return
            }
            self.cachedData = dict
            DispatchQueue.main.async {
                if let minVersion = dict["minVersion"] as? String,
                    minVersion.compare(StoreVersion) == .orderedDescending {
                    self.versionTooLow()
                }
                
                self.featuredView?.removeFromSuperview()
                if let featuredView = FeaturedBaseView.view(dictionary: dict,
                                                            viewController: self,
                                                            tintColor: nil, isActionable: false) as? FeaturedBaseView {
                    featuredView.delegate = self
                    self.featuredView?.removeFromSuperview()
                    self.scrollView?.addSubview(featuredView)
                    self.featuredView = featuredView
                }
                self.viewDidLayoutSubviews()
            }
        }
    }
    
    func versionTooLow() {
        let alertController = UIAlertController(title: String(localizationKey: "Sileo_Update_Required.Title", type: .error),
                                                message: String(localizationKey: "Featured_Requires_Sileo_Update", type: .error),
                                                preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        }))
        self.present(alertController, animated: true, completion: nil)
    }
    
    @objc func updateSileoColors() {
        statusBarStyle = .default
        profileButton?.tintColor = .tintColor
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateSileoColors()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.reloadData()
        updateSileoColors()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.navigationItem.hidesSearchBarWhenScrolling = true
        scrollView?.contentInsetAdjustmentBehavior = .always
        
        self.navigationController?.navigationBar.superview?.tag = WHITE_BLUR_TAG
        self.navigationController?.navigationBar._hidesShadow = true
        
        UIView.animate(withDuration: 0.2) {
            self.profileButton?.alpha = 1.0
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.navigationController?.navigationBar._hidesShadow = false
        
        UIView.animate(withDuration: 0.2) {
            self.profileButton?.alpha = 0
        }
    }
    
    @objc private func updatePicture() {
        if let button = self.profileButton {
            self.profileButton = setPicture(button)
        }
    }
    
    func setPicture(_ button: UIButton) -> UIButton {
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        if !UserDefaults.standard.optionalBool("iCloudProfile", fallback: true) {
            button.setImage(UIImage(named: "User")?.withRenderingMode(.alwaysTemplate), for: .normal)
            button.tintColor = .tintColor
            return button
        }
        #if !targetEnvironment(simulator) && !TARGET_SANDBOX
        let scale = Int(UIScreen.main.scale)
        let filename = scale == 1 ? "AppleAccountIcon": "AppleAccountIcon@\(scale)x"
        if let url = URL(string: "/var/mobile/Library/Caches/com.apple.Preferences/")?
            .appendingPathComponent(filename)
            .appendingPathExtension("png") {
            let toPath = AmyNetworkResolver.shared.cacheDirectory.appendingPathComponent(filename).appendingPathExtension("png")
            spawn(command: "/usr/bin/cp", args: ["/usr/bin/cp", "\(url.path)", "\(toPath.path)"])
            if let data = try? Data(contentsOf: toPath),
               let accountImage = UIImage(data: data) {
                button.setImage(accountImage, for: .normal)
                return button
            }
        }
        #endif
        button.setImage(UIImage(named: "User")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = .tintColor
        return button
    }
    
    func setupProfileButton() {
        let profileButton = setPicture(UIButton())
        
        profileButton.addTarget(self, action: #selector(FeaturedViewController.showProfile(_:)), for: .touchUpInside)
        profileButton.accessibilityIgnoresInvertColors = true
        
        profileButton.layer.cornerRadius = 20
        profileButton.clipsToBounds = true
        profileButton.translatesAutoresizingMaskIntoConstraints = false
        
        if let navigationBar = self.navigationController?.navigationBar {
            navigationBar.addSubview(profileButton)
            if UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft {
                profileButton.leftAnchor.constraint(equalTo: navigationBar.leftAnchor, constant: 16).isActive = true
            } else {
                profileButton.rightAnchor.constraint(equalTo: navigationBar.rightAnchor, constant: -16).isActive = true
            }
            NSLayoutConstraint.activate([
                profileButton.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor, constant: -12)
            ])
        }
        self.profileButton = profileButton
    }
    
    @objc func showProfile(_ sender: Any?) {
        let profileViewController = SettingsViewController(style: .grouped)
        let navController = SettingsNavigationController(rootViewController: profileViewController)
        self.present(navController, animated: true, completion: nil)
    }
    
    func moveAndResizeProfile(height: CGFloat) {
        let delta = height - 44
        let heightDifferenceBetweenStates: CGFloat = 96.5 - 44
        let coeff = delta / heightDifferenceBetweenStates
        
        let factor: CGFloat = 32.0/40.0
        
        let scale = min(1.0, coeff * (1.0 - factor) + factor)
        
        let sizeDiff = 40.0 * (1.0 - factor)
        let maxYTranslation = 12.0 - 6.0 + sizeDiff
        let yTranslation = max(0, min(maxYTranslation, (maxYTranslation - coeff * (6.0 + sizeDiff))))
        
        let xTranslation = max(0, sizeDiff - coeff * sizeDiff)
        profileButton?.transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: xTranslation, y: yTranslation)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let height = self.navigationController?.navigationBar.frame.height else {
            return
        }
        self.moveAndResizeProfile(height: height)
    }
    
    func subviewHeightChanged() {
        self.viewDidLayoutSubviews()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if let featuredHeight = featuredView?.depictionHeight(width: self.view.bounds.width) {
            scrollView?.contentSize = CGSize(width: self.view.bounds.width, height: featuredHeight)
        
            featuredView?.frame = CGRect(origin: .zero, size: CGSize(width: self.view.bounds.width, height: featuredHeight))
        }
        
        self.view.updateConstraintsIfNeeded()
    }
}
