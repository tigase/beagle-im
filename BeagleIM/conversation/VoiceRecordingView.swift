//
// VoiceRecordingView.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//
import AppKit
import AVFoundation

class VoiceRecordingView: NSView, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    
    public let stackView: NSStackView = {
        let stack = NSStackView();
        stack.orientation = .horizontal
        stack.alignment = .centerY;
        stack.distribution = .equalSpacing;
        stack.translatesAutoresizingMaskIntoConstraints = false;
        return stack;
    }();
    
    public let closeBtn: NSButton = {
        let closeBtn = NSButton(image: NSImage(named: "xmark.circle.fill")!, target: self, action: #selector(hideVoiceRecordingView(_:)));
        closeBtn.isBordered = false;
        NSLayoutConstraint.activate([
            closeBtn.widthAnchor.constraint(equalTo: closeBtn.heightAnchor),
            closeBtn.heightAnchor.constraint(equalToConstant: NSFont.systemFontSize * 2)
        ])
        closeBtn.contentTintColor = NSColor.secondaryLabelColor;
        return closeBtn;
    }();
    
    public let sendBtn: NSButton = {
        let sendBtn = NSButton(image: NSImage(named: "paperplane.fill")!, target: self, action: #selector(sendTapped(_:)));
        sendBtn.isBordered = false;
        NSLayoutConstraint.activate([
            sendBtn.widthAnchor.constraint(equalTo: sendBtn.heightAnchor),
            sendBtn.heightAnchor.constraint(equalToConstant: NSFont.systemFontSize * 2)
        ])
        sendBtn.contentTintColor = NSColor.secondaryLabelColor;
        return sendBtn;
    }();
    
    public let actionBtn: NSButton = {
        let btn = NSButton(image: NSImage(named: "stop.circle")!, target: self, action: #selector(actionTapped(_:)));
        btn.isBordered = false;
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalTo: btn.heightAnchor),
            btn.heightAnchor.constraint(equalToConstant: NSFont.systemFontSize * 2)
        ])
        btn.contentTintColor = NSColor.systemRed;
        return btn;
    }();
    
    public let label: NSTextField = {
        let label = NSTextField(labelWithString: "Recording...");
        label.stringValue = NSLocalizedString("Recording", comment: "label to notify user that recording is in progress") + "...";
        label.setContentHuggingPriority(.init(200), for: .horizontal);
        return label;
    }();
    
    private var recordingStartTime: Date?;
    private var recordingEndedTime: Date?;
    private var timer: Timer?;
    
    weak var controller: AbstractChatViewControllerWithSharing?;
    
    private var action: Action = .recording {
        didSet {
            switch action {
            case .playing:
                self.startPlaying();
            case .stopped:
                if oldValue == .playing {
                    self.stopPlaying();
                } else if oldValue == .recording {
                    self.stopRecording();
                }
            default:
                break;
            }
            updateActionButton();
        }
    }
    
    private enum Action {
        case recording
        case stopped
        case playing
                
        var image: NSImage? {
            switch self {
            case .recording:
                return NSImage(named: "stop.circle");
            case .stopped:
                return NSImage(named: "play.circle");
            case .playing:
                return NSImage(named: "stop.circle");
            }
        }
        
        var tintColor: NSColor? {
            switch self {
            case .recording:
                return NSColor.systemRed;
            default:
                return NSColor.secondaryLabelColor;
            }
        }
    }
    
    convenience init() {
        self.init(frame: CGRect(origin: .zero, size: CGSize(width: 100, height: 30)));
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame);
        self.setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        setup();
    }
    
    func setup() {
        self.translatesAutoresizingMaskIntoConstraints = false;

        self.addSubview(stackView);

        self.closeBtn.target = self;
        self.actionBtn.target = self;
        self.sendBtn.target = self;
        
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10);
        stackView.setHuggingPriority(.defaultHigh, for: .horizontal);
        stackView.setHuggingPriority(.defaultHigh, for: .vertical);
        stackView.spacing = 6;
        stackView.alignment = .centerY;
        stackView.addArrangedSubview(closeBtn);
        stackView.addArrangedSubview(actionBtn);
        stackView.distribution = .fill;
        stackView.addArrangedSubview(label);
        stackView.addArrangedSubview(sendBtn);
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
        
        updateActionButton();
    }
    
    @objc func hideVoiceRecordingView(_ sender: Any) {
        self.removeFromSuperview();
        stopRecording();
        reset();
    }
    
    func reset() {
        self.recordingEndedTime = nil;
        self.recordingStartTime = nil;
        self.fileUrl = nil;
        audioRecorder?.stop();
        audioRecorder = nil;
        timer?.invalidate();
        timer = nil;
        if let fileUrl = self.fileUrl {
            try? FileManager.default.removeItem(at: fileUrl);
        }
    }
    
    private var encoding: EncodingFormat = .MPEG4AAC;
    private var fileUrl: URL?;
    private var audioRecorder: AVAudioRecorder?;
    
    func startRecording() {
        reset();
        
        fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)\(encoding.extensions)")
        
        recordingStartTime = Date();
        updateTime();
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
            self?.updateTime();
        })
        
        let settings = encoding.settings;
         
        do {
            audioRecorder = try AVAudioRecorder(url: fileUrl!, settings: settings);
            audioRecorder?.delegate = self;
            audioRecorder?.record();
        } catch {
            reset();
            hideVoiceRecordingView(self);
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop();
        audioRecorder = nil;
        recordingEndedTime = Date();
        timer?.invalidate();
        timer = nil;
        updateTime();
    }
    
    private var audioPlayer: AVAudioPlayer?;
    
    private enum EncodingFormat {
        case OPUS
        case MPEG4AAC
        
        var settings: [String: Any] {
            switch self {
            case .OPUS:
                return [AVFormatIDKey: kAudioFormatOpus, AVNumberOfChannelsKey: 1, AVSampleRateKey: 12000.0] as [String: Any];
            case .MPEG4AAC:
                return [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1, AVSampleRateKey: 12000.0, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue] as [String: Any]
            }
        }
        
        var extensions: String {
            switch self {
            case .OPUS:
                return ".oga";
            case .MPEG4AAC:
                return ".m4a";
            }
        }
        
        var mimetype: String {
            switch self {
            case .OPUS:
                return "audio/ogg";
            case .MPEG4AAC:
                return "audio/mp4";
            }
        }
    }
    
    func startPlaying() {
        guard let fileUrl = self.fileUrl else {
            self.hideVoiceRecordingView(self);
            return;
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileUrl)
            audioPlayer?.delegate = self;
            audioPlayer?.play();
        } catch {
            self.hideVoiceRecordingView(self);
        }
    }
    
    func stopPlaying() {
        audioPlayer?.stop();
        audioPlayer = nil;
        self.action = .stopped;
    }
    
    static let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter();
        formatter.unitsStyle = .abbreviated;
        formatter.zeroFormattingBehavior = .dropAll;
        formatter.allowedUnits = [.minute,.second]
        return formatter;
    }();
    
    func updateTime() {
        guard let start = recordingStartTime else {
            return;
        }
        let diff = (recordingEndedTime ?? Date()).timeIntervalSince(start);
        switch self.action {
        case .recording:
            self.label.stringValue = "\(NSLocalizedString("Recording", comment: "label to notify user that recording is in progress"))... \(VoiceRecordingView.timeFormatter.string(from: diff) ?? "")";
        case .stopped:
            self.label.stringValue = "\(NSLocalizedString("Recorded", comment: "label to notify user that we record")): \(VoiceRecordingView.timeFormatter.string(from: diff) ?? "")";
        case .playing:
            self.label.stringValue = NSLocalizedString("Playing", comment: "label to notify user that playing is in progress") + "...";
        }
    }
    
    func updateActionButton() {
        actionBtn.image = action.image;
        actionBtn.contentTintColor = action.tintColor;
        updateTime();
    }
    
    @objc func actionTapped(_ sender: Any) {
        switch action {
        case .recording, .playing:
            action = .stopped;
        case .stopped:
            action = .playing;
        }
    }
    
    @objc func sendTapped(_ sender: Any) {
        guard let url = self.fileUrl, let controller = self.controller else {
            return;
        }
        audioRecorder?.stop();
        self.fileUrl = nil;
        
        let task = FileURLSharingTaskItem(chat: controller.conversation, url: url, deleteFileOnCompletion: true);
        SharingTaskManager.instance.share(task: SharingTaskManager.SharingTask(controller: controller, items: [task], imageQuality: .original, videoQuality: .original));
        self.hideVoiceRecordingView(self);
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("recording finished:", flag);
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.stopPlaying();
    }
}
