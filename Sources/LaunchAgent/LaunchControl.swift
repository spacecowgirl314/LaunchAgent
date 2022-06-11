//
//  LaunchControl.swift
//  LaunchAgent
//
//  Created by Emory Dunn on 2018-02-19.
//

import Foundation
import SystemConfiguration

/// Errors related to controlling jobs
public enum LaunchControlError: Error, LocalizedError {
    
    /// The URL is not set for the specified agent
    case urlNotSet(label: String)
    
    /// Description of the error
    public var localizedDescription: String {
        switch self {
        case .urlNotSet(let label):
            return "The URL is not set for agent \(label)"
        }
    }
}

/// Control agents and daemons.
public class LaunchControl {
    
    /// The shared instance
    public static let shared = LaunchControl()
    
    static let launchctl = "/bin/launchctl"
    
    
    let encoder = PropertyListEncoder()
    let decoder = PropertyListDecoder()
    
    private var uid: uid_t = 0
    private var gid: gid_t = 0
    
    init() {
        SCDynamicStoreCopyConsoleUser(nil, &uid, &gid)
        
        encoder.outputFormat = .xml
    }
    
    /// Provides the user's LaunchAgent directory
    ///
    /// - Note: If run in a sandbox the directory returned will be inside the application's container
    ///
    /// - Returns: ~/Library/LaunchAgent
    /// - Throws: FileManager errors
    func launchAgentsURL() throws -> URL {
        let library = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

        return library.appendingPathComponent("LaunchAgents")
    }
    
    /// Read a LaunchAgent from the user's LaunchAgents directory
    ///
    /// - Parameter called: file name of the job
    /// - Returns: a LaunchAgent instance
    /// - Throws: errors on decoding the property list
    public func read(agent called: String) throws -> LaunchAgent {
        let url = try launchAgentsURL().appendingPathComponent(called)
        
        return try read(from: url)
    }
    
    /// Read a LaunchAgent from disk
    ///
    /// - Parameter url: url of the property list
    /// - Returns:a LaunchAgent instance
    /// - Throws: errors on decoding the property list
    public func read(from url: URL) throws -> LaunchAgent {
        let agent = try decoder.decode(LaunchAgent.self, from: Data(contentsOf: url))
        agent.url = url
        return agent
    }

    /// Writes a LaunchAgent to disk as a property list into the user's LaunchAgents directory
    ///
    /// The agent's label will be used as the filename with a `.plist` extension.
    ///
    /// - Parameters:
    ///   - agent: the agent to encode
    /// - Throws: errors on encoding the property list
    public func write(_ agent: LaunchAgent) throws {
        let url = try launchAgentsURL().appendingPathComponent("\(agent.label).plist")
        
        try write(agent, to: url)
    }
    
    /// Writes a LaunchAgent to disk as a property list into the user's LaunchAgents directory
    ///
    /// - Parameters:
    ///   - agent: the agent to encode
    ///   - called: the file name of the job
    /// - Throws: errors on encoding the property list
    public func write(_ agent: LaunchAgent, called: String) throws {
        let url = try launchAgentsURL().appendingPathComponent(called)
        
        try write(agent, to: url)
    }
    
    /// Writes a LaunchAgent to disk as a property list to the specified URL
    ///
    /// `.plist` will be appended to the URL if needed
    ///
    /// - Parameters:
    ///   - agent: the agent to encode
    ///   - called: the url at which to write
    /// - Throws: errors on encoding the property list
    public func write(_ agent: LaunchAgent, to url: URL) throws {
        var url = url
        if url.pathExtension != "plist" {
            url.appendPathExtension("plist")
        }
        try encoder.encode(agent).write(to: url)
        
        agent.url = url
    }
    
    /// Sets the provided LaunchAgent's URL based on its `label`
    ///
    /// - Parameter agent: the LaunchAgent
    /// - Throws: errors when reading directory contents
    public func setURL(for agent: LaunchAgent) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: try launchAgentsURL(),
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants, .skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        
        contents.forEach { url in
            let testAgent = try? self.read(from: url)
            
            if agent.label == testAgent?.label {
                agent.url = url
                return
            }
        }
        
        
    }
    
}

// MARK: - Job control
extension LaunchControl {
    /// Run `launchctl start` on the agent
    ///
    /// Check the status of the job with `.status(_: LaunchAgent)`
    public func start(_ agent: LaunchAgent) {
        let arguments = ["start", agent.label]
        Process.launchedProcess(launchPath: LaunchControl.launchctl, arguments: arguments)
    }
    
    /// Run `launchctl stop` on the agent
    ///
    /// Check the status of the job with `.status(_: LaunchAgent)`
    public func stop(_ agent: LaunchAgent) {
        let arguments = ["stop", agent.label]
        Process.launchedProcess(launchPath: LaunchControl.launchctl, arguments: arguments)
    }
    
    /// Run `launchctl load` on the agent
    ///
    /// Check the status of the job with `.status(_: LaunchAgent)`
    @available(macOS, deprecated: 10.11)
    public func load(_ agent: LaunchAgent) throws {
        guard let agentURL = agent.url else {
            throw LaunchControlError.urlNotSet(label: agent.label)
        }
        
        let arguments = ["load", agentURL.path]
        Process.launchedProcess(launchPath: LaunchControl.launchctl, arguments: arguments)
    }
    
    /// Run `launchctl unload` on the agent
    ///
    /// Check the status of the job with `.status(_: LaunchAgent)`
    @available(macOS, deprecated: 10.11)
    public func unload(_ agent: LaunchAgent) throws {
        guard let agentURL = agent.url else {
            throw LaunchControlError.urlNotSet(label: agent.label)
        }
        
        let arguments = ["unload", agentURL.path]
        Process.launchedProcess(launchPath: LaunchControl.launchctl, arguments: arguments)
    }
    
    /// Run `launchctl bootstrap` on the agent
    ///
    /// Check the status of the job with `.status(_: LaunchAgent)`
    @available(macOS, introduced: 10.11)
    public func bootstrap(_ agent: LaunchAgent) throws {
        guard let agentURL = agent.url else {
            throw LaunchControlError.urlNotSet(label: agent.label)
        }
        
        let arguments = ["bootstrap", "gui/\(uid)", agentURL.path]
        let process = Process.launchedProcess(launchPath: LaunchControl.launchctl, arguments: arguments)
        process.waitUntilExit()
    }
    
    /// Run `launchctl bootout` on the agent
    ///
    /// Check the status of the job with `.status(_: LaunchAgent)`
    @available(macOS, introduced: 10.11)
    public func bootout(_ agent: LaunchAgent) throws {
        guard let agentURL = agent.url else {
            throw LaunchControlError.urlNotSet(label: agent.label)
        }
        
        let arguments = ["bootout", "gui/\(uid)", agentURL.path]
        let process = Process.launchedProcess(launchPath: LaunchControl.launchctl, arguments: arguments)
        process.waitUntilExit()
    }
    
    /// Retreives the status of the LaunchAgent from `launchctl`
    ///
    /// - Returns: the agent's status
    public func status(_ agent: LaunchAgent) -> AgentStatus {
        // Adapted from https://github.com/zenonas/barmaid/blob/master/Barmaid/LaunchControl.swift
        
        let launchctlTask = Process()
        let grepTask = Process()
        let cutTask = Process()
        
        launchctlTask.launchPath = "/bin/launchctl"
        launchctlTask.arguments = ["list"]
        
        grepTask.launchPath = "/usr/bin/grep"
        grepTask.arguments = [agent.label]
        
        cutTask.launchPath = "/usr/bin/cut"
        cutTask.arguments = ["-f1"]
        
        let pipeLaunchCtlToGrep = Pipe()
        launchctlTask.standardOutput = pipeLaunchCtlToGrep
        grepTask.standardInput = pipeLaunchCtlToGrep
        
        let pipeGrepToCut = Pipe()
        grepTask.standardOutput = pipeGrepToCut
        cutTask.standardInput = pipeGrepToCut
        
        let pipeCutToFile = Pipe()
        cutTask.standardOutput = pipeCutToFile
        
        let fileHandle: FileHandle = pipeCutToFile.fileHandleForReading as FileHandle
        
        launchctlTask.launch()
        grepTask.launch()
        cutTask.launch()
        
        
        let data = fileHandle.readDataToEndOfFile()
        let stringResult = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""

        switch stringResult {
        case "-":
            return .loaded
        case "":
            return .unloaded
        default:
            return .running(pid: Int(stringResult)!)
        }
    }
}
