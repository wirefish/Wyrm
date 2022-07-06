//
//  Extensions.swift
//  Wyrm
//
//  General-purpose extensions of built-in types.
//

extension Array {
    // Returns the first non-nil value obtained by applying a transform to the
    // elements of the array.
    func firstMap<T>(_ transform: (Element) -> T?) -> T? {
        for value in self {
            if let transformedValue = transform(value) {
                return transformedValue
            }
        }
        return nil
    }

    func keep(where pred: (Element) -> Bool) -> [Element] {
        compactMap { pred($0) ? $0 : nil }
    }
}

extension Substring {
    func trimmed(_ pred: (Character) -> Bool) -> Substring {
        if let first = firstIndex(where: { !pred($0) }),
           let last = lastIndex(where: { !pred($0) }) {
            return self[first...last]
        } else {
            return Substring()
        }
    }
}
