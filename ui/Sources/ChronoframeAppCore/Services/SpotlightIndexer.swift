#if canImport(CoreSpotlight)
import CoreSpotlight
import UniformTypeIdentifiers
import Foundation

@MainActor
public final class SpotlightIndexer {
    public static func indexHistoryEntries(_ entries: [RunHistoryEntry]) {
        // Skip during tests to prevent headless failures or sandbox errors
        guard NSClassFromString("XCTestCase") == nil else { return }
        
        Task.detached(priority: .background) {
            let items = entries.compactMap { entry -> CSSearchableItem? in
                guard entry.kind == .auditReceipt || entry.kind == .dedupeAuditReceipt || entry.kind == .reorganizeAuditReceipt else {
                    return nil
                }
                
                let attributeSet = CSSearchableItemAttributeSet(contentType: .json)
                attributeSet.title = entry.title
                attributeSet.contentDescription = "Chronoframe run receipt: \(entry.relativePath) (\(entry.createdAt.formatted()))"
                attributeSet.contentModificationDate = entry.createdAt
                if let size = entry.fileSizeBytes {
                    attributeSet.fileSize = NSNumber(value: size)
                }
                attributeSet.keywords = ["Chronoframe", "Organize", "Deduplicate", "Run Receipt", "Audit", entry.title]
                
                return CSSearchableItem(
                    uniqueIdentifier: entry.path,
                    domainIdentifier: "com.chronoframe.runs",
                    attributeSet: attributeSet
                )
            }
            
            guard !items.isEmpty else { return }
            
            do {
                try await CSSearchableIndex.default().indexSearchableItems(items)
            } catch {
                print("Failed to index Spotlight items: \(error)")
            }
        }
    }
    
    public static func deindexHistoryEntry(path: String) {
        // Skip during tests
        guard NSClassFromString("XCTestCase") == nil else { return }
        
        Task.detached(priority: .background) {
            do {
                try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [path])
            } catch {
                print("Failed to delete Spotlight items: \(error)")
            }
        }
    }
}
#endif
