//
//  MusicPlayer.swift
//  mupl
//
//  Created by Tamerlan Satualdypov on 19.02.2024.
//

import Foundation
import Combine
import MusicKit
import ISSoundAdditions

final class MusicPlayer: ObservableObject {
    typealias PlaybackStatus = MusicKit.MusicPlayer.PlaybackStatus
    typealias ShuffleMode = MusicKit.MusicPlayer.ShuffleMode
    typealias RepeatMode = MusicKit.MusicPlayer.RepeatMode
    
    enum ActionDirection {
        case forward
        case backward
    }
    
    private let player: ApplicationMusicPlayer = .shared
    
    private var playbackTimeCancellable: AnyCancellable?
    private var playerStateCancellable: AnyCancellable?
    private var playerQueueCancellable: AnyCancellable?
    
    @Published var queue: [Song] = []
    @Published var currentSong: Song? = nil
    @Published var playbackTime: TimeInterval = 0.0
    
    @Published private(set) var playbackStatus: PlaybackStatus = .stopped {
        didSet {
            self.updatePlaybackTimeObservation()
        }
    }
    
    @Published var shuffleMode: ShuffleMode = .off {
        didSet {
            self.player.state.shuffleMode = self.shuffleMode
        }
    }
    
    @Published var repeatMode: RepeatMode = .none {
        didSet {
            self.player.state.repeatMode = self.repeatMode
        }
    }
    
    init() {
        self.playerStateCancellable = self.player.state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in
                self.updateState()
            }
        
        self.playerQueueCancellable = self.player.queue.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in
                self.updateQueue()
            }
    }
    
    func play(item: PlayableMusicItem? = nil) {
        Task {
            if let item = item {
                self.player.queue = [item]
            }
            
            try await self.player.prepareToPlay()
            try await self.player.play()
        }
    }
    
    func skip(_ direction: ActionDirection = .forward) {
        switch direction {
        case .forward:
            self.handleForwardSkipping()
        case .backward:
            self.handleBackwardSkipping()
        }
    }
    
    func seek(to time: TimeInterval) {
        self.player.playbackTime = time
    }
    
    func pause() {
        guard self.playbackStatus != .paused else { return }
        self.player.pause()
    }
    
    func stop() {
        guard self.playbackStatus != .stopped else { return }
        self.player.stop()
    }
    
    private func handleForwardSkipping() {
        Task {
            try await self.player.skipToNextEntry()
            
            if
                case .song(let song) = self.player.queue.entries.last?.item,
                song == self.currentSong
            {
                self.player.queue = []
                self.currentSong = nil
            }
        }
    }
    
    private func handleBackwardSkipping() {
        Task {
            try await self.player.skipToPreviousEntry()
            
            if 
                case .song(let song) = self.player.queue.entries.first?.item,
                song == self.currentSong
            {
                self.currentSong = nil
            }
        }
    }
    
    private func runPlaybackTimeObservation() {
        self.playbackTimeCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                self.playbackTime = self.player.playbackTime
            }
    }
    
    private func pausePlaybackTimeObservation() {
        self.playbackTimeCancellable = nil
    }
    
    private func stopPlaybackTimeObservation() {
        self.playbackTime = 0.0
        self.playbackTimeCancellable = nil
    }
    
    private func updatePlaybackTimeObservation() {
        switch self.playbackStatus {
        case .playing:
            self.runPlaybackTimeObservation()
        case .paused, .interrupted, .seekingForward, .seekingBackward:
            self.pausePlaybackTimeObservation()
        case .stopped:
            self.stopPlaybackTimeObservation()
        @unknown default:
            break
        }
    }
    
    private func updateState() {
        self.playbackStatus = self.player.state.playbackStatus
        self.shuffleMode = self.player.state.shuffleMode ?? .off
        self.repeatMode = self.player.state.repeatMode ?? .none
    }
    
    private func updateQueue() {
        self.queue = self.player.queue.entries.compactMap { entry in
            guard
                let item = entry.item,
                case .song(let song) = item
            else { return nil }
            
            return song
        }
        
        if case .song(let song) = self.player.queue.currentEntry?.item {
            self.currentSong = song
        } else {
            self.currentSong = nil
        }
    }
}
