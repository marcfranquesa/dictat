import Foundation

/// Overlap-merge utility for adjacent ASR token windows.
///
/// This is the trimmed subset of FluidAudio's `ChunkProcessor` retained for the
/// Parakeet Unified offline batch path (`UnifiedAsrManager`): each 15 s window
/// is decoded independently and adjacent token streams are reconciled on their
/// 2 s overlap via `mergeChunks` (time-tolerant token matching with
/// SentencePiece word-boundary splicing). The TDT sliding-window transcription
/// pipeline that originally lived alongside this code is not part of the
/// vendored Parakeet Unified path and has been removed.
struct ChunkProcessor {
    let sampleSource: AudioSampleSource
    let totalSamples: Int

    typealias TokenWindow = (token: Int, timestamp: Int, confidence: Float, duration: Int)
    private struct IndexedToken {
        let index: Int
        let token: TokenWindow
        let start: Double
        let end: Double
    }

    // 2.0s overlap (frame-aligned) gives the decoder slack when merging windows.
    let overlapSeconds: Double = 2.0

    /// Initialize with a streaming audio sample source.
    init(sampleSource: AudioSampleSource) {
        self.sampleSource = sampleSource
        self.totalSamples = sampleSource.sampleCount
    }

    /// Convenience initializer for in-memory audio samples.
    init(audioSamples: [Float]) {
        self.init(sampleSource: ArrayAudioSampleSource(samples: audioSamples))
    }

    /// Check if a token string indicates a SentencePiece/TDT word boundary.
    static func isWordBoundary(_ token: String) -> Bool {
        token.hasPrefix(ASRConstants.sentencePieceWordBoundary) || token.hasPrefix(" ")
    }

    /// Token IDs whose vocabulary piece may safely start the portion spliced
    /// in from the `right` window at a seam: SentencePiece word-initial pieces
    /// (`▁` prefix) or punctuation-only pieces (which attach to the previous
    /// word by design). Returns nil for an empty vocabulary so merge behavior
    /// is unchanged when no vocabulary is available (issue #683).
    static func spliceSafeTokenIds(vocabulary: [Int: String]) -> Set<Int>? {
        guard !vocabulary.isEmpty else { return nil }
        var ids = Set<Int>()
        for (id, piece) in vocabulary where isSpliceSafePiece(piece) {
            ids.insert(id)
        }
        return ids
    }

    /// A piece is splice-safe when decoding it right after another word does
    /// not glue two words together: it either starts a new word (`▁`/space
    /// prefix) or is pure punctuation/symbols.
    static func isSpliceSafePiece(_ piece: String) -> Bool {
        guard !piece.isEmpty else { return false }
        if isWordBoundary(piece) { return true }
        return piece.unicodeScalars.allSatisfy { scalar in
            CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }
    }

    func mergeChunks(
        _ left: [TokenWindow],
        _ right: [TokenWindow],
        spliceSafeTokenIds: Set<Int>? = nil
    ) -> [TokenWindow] {
        if left.isEmpty { return right }
        if right.isEmpty { return left }

        let frameDuration = ASRConstants.secondsPerEncoderFrame
        let overlapDuration = overlapSeconds
        let halfOverlapWindow = overlapDuration / 2

        func startTime(of token: TokenWindow) -> Double {
            Double(token.timestamp) * frameDuration
        }

        func endTime(of token: TokenWindow) -> Double {
            startTime(of: token) + frameDuration
        }

        let leftEndTime = endTime(of: left.last!)
        let rightStartTime = startTime(of: right.first!)

        if leftEndTime <= rightStartTime {
            return left + right
        }

        let overlapLeft: [IndexedToken] = left.enumerated().compactMap { offset, token in
            let start = startTime(of: token)
            let end = start + frameDuration
            guard end > rightStartTime - overlapDuration else { return nil }
            return IndexedToken(index: offset, token: token, start: start, end: end)
        }

        let overlapRight: [IndexedToken] = right.enumerated().compactMap { offset, token in
            let start = startTime(of: token)
            guard start < leftEndTime + overlapDuration else { return nil }
            return IndexedToken(index: offset, token: token, start: start, end: start + frameDuration)
        }

        guard overlapLeft.count >= 2 && overlapRight.count >= 2 else {
            return mergeByMidpoint(
                left: left, right: right, leftEndTime: leftEndTime, rightStartTime: rightStartTime,
                frameDuration: frameDuration, spliceSafeTokenIds: spliceSafeTokenIds)
        }

        let minimumPairs = max(overlapLeft.count / 2, 1)

        // EXTRACTED: Contiguous matching using SequenceMatcher
        let timeTolerantMatcher: (IndexedToken, IndexedToken) -> Bool = { [self] l, r in
            tokensMatch(l, r, tolerance: halfOverlapWindow)
        }

        let contiguousMatches = SequenceMatcher.findContiguousMatches(
            left: overlapLeft,
            right: overlapRight,
            matcher: timeTolerantMatcher
        )

        // Convert SequenceMatch results to index pairs
        let contiguousPairs = contiguousMatches.map { ($0.leftStartIndex, $0.rightStartIndex) }

        if contiguousPairs.count >= minimumPairs {
            return mergeUsingMatches(
                matches: contiguousPairs,
                overlapLeft: overlapLeft,
                overlapRight: overlapRight,
                left: left,
                right: right,
                spliceSafeTokenIds: spliceSafeTokenIds
            )
        }

        // EXTRACTED: LCS fallback using SequenceMatcher
        let lcsMatches = SequenceMatcher.findLongestCommonSubsequence(
            left: overlapLeft,
            right: overlapRight,
            matcher: timeTolerantMatcher
        )

        guard !lcsMatches.isEmpty else {
            return mergeByMidpoint(
                left: left, right: right, leftEndTime: leftEndTime, rightStartTime: rightStartTime,
                frameDuration: frameDuration, spliceSafeTokenIds: spliceSafeTokenIds)
        }

        // Map LCS matches directly to pairs (no consolidation)
        // mergeUsingMatches requires one pair per matched element to function correctly
        let lcsPairs = lcsMatches.map { ($0.leftStartIndex, $0.rightStartIndex) }

        return mergeUsingMatches(
            matches: lcsPairs,
            overlapLeft: overlapLeft,
            overlapRight: overlapRight,
            left: left,
            right: right,
            spliceSafeTokenIds: spliceSafeTokenIds
        )
    }

    private func tokensMatch(_ left: IndexedToken, _ right: IndexedToken, tolerance: Double) -> Bool {
        guard left.token.token == right.token.token else { return false }
        let timeDifference = abs(left.start - right.start)
        return timeDifference < tolerance
    }

    private func mergeUsingMatches(
        matches: [(Int, Int)],
        overlapLeft: [IndexedToken],
        overlapRight: [IndexedToken],
        left: [TokenWindow],
        right: [TokenWindow],
        spliceSafeTokenIds: Set<Int>?
    ) -> [TokenWindow] {
        let leftIndices = matches.map { overlapLeft[$0.0].index }
        let rightIndices = matches.map { overlapRight[$0.1].index }

        var result: [TokenWindow] = []

        if let firstLeft = leftIndices.first, firstLeft > 0 {
            result.append(contentsOf: left[..<firstLeft])
        }

        for idx in 0..<matches.count {
            let leftIndex = leftIndices[idx]
            let rightIndex = rightIndices[idx]

            result.append(left[leftIndex])

            guard idx < matches.count - 1 else { continue }

            let nextLeftIndex = leftIndices[idx + 1]
            let nextRightIndex = rightIndices[idx + 1]

            let gapLeft = nextLeftIndex > leftIndex + 1 ? Array(left[(leftIndex + 1)..<nextLeftIndex]) : []
            let gapRight = nextRightIndex > rightIndex + 1 ? Array(right[(rightIndex + 1)..<nextRightIndex]) : []

            if gapRight.count > gapLeft.count {
                result.append(contentsOf: gapRight)
            } else {
                result.append(contentsOf: gapLeft)
            }
        }

        if let lastRight = rightIndices.last, lastRight + 1 < right.count {
            let tail = right[(lastRight + 1)...]
            if let safeIds = spliceSafeTokenIds,
                let firstTail = tail.first,
                !safeIds.contains(firstTail.token)
            {
                // Issue #683: the splice lands mid-word — right's first
                // post-match piece continues the word containing the matched
                // anchor, so splicing here can decode a left-prefix +
                // right-suffix hybrid or glue two words together. Re-splice
                // at a word boundary so exactly one window segments the
                // seam word.
                if let wordStart = wordInitialIndex(in: right, endingAt: lastRight, safeIds: safeIds),
                    popSeamWord(from: &result, safeIds: safeIds)
                {
                    // The right window heard the seam word from its start —
                    // adopt its segmentation of the whole word. (The left
                    // window's chunk often ends mid-word here, so its view
                    // of the word is the truncated one.)
                    result.append(contentsOf: right[wordStart...])
                } else {
                    // The right window was cut mid-word at its stream start
                    // (no word-initial piece before the anchor): the left
                    // window owns the seam word. Complete it with left's own
                    // continuation pieces and resume right at its next
                    // word-initial piece instead of gluing.
                    if let lastLeft = leftIndices.last {
                        var cursor = lastLeft + 1
                        while cursor < left.count, !safeIds.contains(left[cursor].token) {
                            result.append(left[cursor])
                            cursor += 1
                        }
                    }
                    if let resume = tail.firstIndex(where: { safeIds.contains($0.token) }) {
                        result.append(contentsOf: tail[resume...])
                    }
                }
            } else {
                result.append(contentsOf: tail)
            }
        }

        return result
    }

    /// Index of the word-initial (or punctuation) piece starting the word
    /// that contains `anchor`, or nil when the stream begins mid-word.
    private func wordInitialIndex(
        in stream: [TokenWindow],
        endingAt anchor: Int,
        safeIds: Set<Int>
    ) -> Int? {
        var index = anchor
        while index >= 0 {
            if safeIds.contains(stream[index].token) { return index }
            index -= 1
        }
        return nil
    }

    /// Remove the trailing seam word (continuation pieces plus its
    /// word-initial piece) from `result` so the right window's segmentation
    /// of the same word can replace it. Returns false — leaving `result`
    /// untouched — when no word-initial piece exists within a plausible
    /// word length.
    private func popSeamWord(from result: inout [TokenWindow], safeIds: Set<Int>) -> Bool {
        let maxPiecesPerWord = 12
        var cursor = result.count - 1
        var inspected = 0
        while cursor >= 0, inspected < maxPiecesPerWord {
            if safeIds.contains(result[cursor].token) {
                result.removeLast(result.count - cursor)
                return true
            }
            cursor -= 1
            inspected += 1
        }
        return false
    }

    private func mergeByMidpoint(
        left: [TokenWindow],
        right: [TokenWindow],
        leftEndTime: Double,
        rightStartTime: Double,
        frameDuration: Double,
        spliceSafeTokenIds: Set<Int>?
    ) -> [TokenWindow] {
        let cutoff = (leftEndTime + rightStartTime) / 2
        // Token streams are emitted in timestamp order, so the cutoff filter
        // is equivalent to a prefix/suffix split.
        var leftEnd = left.firstIndex { Double($0.timestamp) * frameDuration >= cutoff } ?? left.count
        var rightStart = right.firstIndex { Double($0.timestamp) * frameDuration >= cutoff } ?? right.count
        if let safeIds = spliceSafeTokenIds {
            // Issue #683: a pure time cutoff can split a word. Extend the
            // left stream until the word it started is complete, and drop
            // orphaned continuation pieces (whose word-initial piece was
            // trimmed away) from the head of the right stream.
            if leftEnd > 0 {
                while leftEnd < left.count, !safeIds.contains(left[leftEnd].token) {
                    leftEnd += 1
                }
            }
            while rightStart < right.count, !safeIds.contains(right[rightStart].token) {
                rightStart += 1
            }
        }
        return Array(left[..<leftEnd]) + Array(right[rightStart...])
    }
}
