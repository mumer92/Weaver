//
//  SourceKit.swift
//  WeaverCodeGen
//
//  Created by Théophane Rupin on 2/22/18.
//

import Foundation
import SourceKittenFramework

// MARK: - Annotation

struct SourceKitDependencyAnnotation {
    
    let annotationString: String
    let offset: Int
    let length: Int
    let name: String
    let type: ConcreteType?
    let abstractTypes: Set<AbstractType>
    let dependencyKind: Dependency.Kind?
    let accessLevel: AccessLevel
    let configurationAttributes: [ConfigurationAttribute]
    
    init?(_ dictionary: [String: Any], lines: [(content: String, range: NSRange)]) throws {
        
        guard let kindString = dictionary[SwiftDocKey.kind.rawValue] as? String,
              let kind = SwiftDeclarationKind(rawValue: kindString),
              kind == .varInstance else {
            return nil
        }
        
        guard let offset = dictionary[SwiftDocKey.offset.rawValue] as? Int64 else {
            return nil
        }
        self.offset = Int(offset)
        
        guard let length = dictionary[SwiftDocKey.length.rawValue] as? Int64 else {
            return nil
        }
        self.length = Int(length)
        
        guard let name = dictionary[SwiftDocKey.name.rawValue] as? String else {
            return nil
        }
        self.name = name
        
        guard let typename = dictionary[SwiftDocKey.typeName.rawValue] as? String else {
            return nil
        }
        
        abstractTypes = Set(try typename.split(separator: "&").lazy.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.compactMap { typeString in
            let components = typeString.split(separator: " ").map { $0.trimmingCharacters(in: .whitespaces) }
            if let lastComponent = components.last {
                return try AbstractType(lastComponent)
            } else {
                return try AbstractType(typeString)
            }
        })
        
        if let accessLevelString = dictionary["key.accessibility"] as? String {
            accessLevel = AccessLevel(accessLevelString)
        } else {
            accessLevel = .default
        }
        
        guard let attributes = dictionary["key.attributes"] as? [[String: Any]] else {
            return nil
        }
        
        guard let annotation = attributes.first(where: { $0["key.attribute"] as? String == "source.decl.attribute._custom" }),
              let annotationOffset = annotation[SwiftDocKey.offset.rawValue] as? Int64,
              let annotationLength = annotation[SwiftDocKey.length.rawValue] as? Int64,
              let annotationLineStartIndex = lines.firstIndex(where: { $0.range.contains(Int(annotationOffset)) }),
              let annotationLineEndIndex = lines.firstIndex(where: { $0.range.contains(Int(annotationOffset + annotationLength)) }) else {
            return nil
        }
        
        let annotationString = lines[annotationLineStartIndex...annotationLineEndIndex]
            .map { $0.content.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        self.annotationString = annotationString
        
        guard let annotationBuilder = try SourceKitDependencyAnnotation.parseBuilder(annotationString) else {
            return nil
        }

        dependencyKind = annotationBuilder.dependencyKind
        type = annotationBuilder.concreteType
        configurationAttributes = annotationBuilder.configurationAttributes
    }
    
    private static func parseBuilder(_ annotationString: String) throws -> (
        dependencyKind: Dependency.Kind?,
        concreteType: ConcreteType?,
        configurationAttributes: [ConfigurationAttribute]
    )? {
        guard var startIndex = annotationString.firstIndex(where: { $0 == "@" }) else { return nil }
        guard var endIndex = annotationString.firstIndex(where: { $0 == ")" }) else { return nil }
        guard annotationString[startIndex] == "@" else { return nil }
        startIndex = annotationString.index(after: startIndex)
        endIndex = annotationString.index(after: endIndex)
        guard startIndex < endIndex, endIndex <= annotationString.endIndex else { return nil }
        let annotationString = String(annotationString[startIndex..<endIndex])

        let dictionary = try Structure(file: File(contents: annotationString)).dictionary
        guard let structures = dictionary[SwiftDocKey.substructure.rawValue] as? [[String: Any]] else { return nil }
        guard let structure = structures.first else { return nil }
        
        guard let annotationTypeString = structure[SwiftDocKey.name.rawValue] as? String else { return nil }
        guard annotationTypeString.hasSuffix("Dependency") else { return nil }

        var concreteType: ConcreteType?
        var configurationAttributes = [ConfigurationAttribute]()
        var dependencyKind: Dependency.Kind?

        let arguments = (structure[SwiftDocKey.substructure.rawValue] as? [[String: Any]]) ?? []
        if arguments.isEmpty {
            let dependencyKindString = annotationString
                .replacingOccurrences(of: annotationTypeString, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            dependencyKind = Dependency.Kind(dependencyKindString)
        }

        for argument in arguments {
            guard argument[SwiftDocKey.kind.rawValue] as? String == "source.lang.swift.expr.argument" else { continue }
            guard let offset = argument[SwiftDocKey.offset.rawValue] as? Int64 else { continue }
            guard let length = argument[SwiftDocKey.length.rawValue] as? Int64 else { continue }

            if let attributeName = argument[SwiftDocKey.name.rawValue] as? String {
                let startIndex = annotationString.index(annotationString.startIndex, offsetBy: Int(offset))
                let endIndex = annotationString.index(startIndex, offsetBy: Int(length))
                let keyValueString = String(annotationString[startIndex..<endIndex])
                let keyValue = keyValueString.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let value = keyValue.last else { continue }

                if attributeName == "type" {
                    concreteType = try ConcreteType(value.replacingOccurrences(of: ".self", with: ""))
                } else {
                    configurationAttributes.append(
                        try ConfigurationAttribute(name: attributeName, valueString: value)
                    )
                }
            } else {
                let startIndex = annotationString.index(annotationString.startIndex, offsetBy: Int(offset))
                let endIndex = annotationString.index(startIndex, offsetBy: Int(length))
                let valueString = String(annotationString[startIndex..<endIndex])
                dependencyKind = Dependency.Kind(valueString)
            }
        }
        
        return (dependencyKind, concreteType, configurationAttributes)
    }
}

// MARK: - Type

struct SourceKitTypeDeclaration {
    
    let offset: Int
    let length: Int
    let type: ConcreteType
    let hasBody: Bool
    let accessLevel: AccessLevel
    let isInjectable: Bool
    
    init?(_ dictionary: [String: Any], lineString: String = "") {
        
        guard let kindString = dictionary[SwiftDocKey.kind.rawValue] as? String,
              let kind = SwiftDeclarationKind(rawValue: kindString) else {
            return nil
        }
        
        guard let offset = dictionary[SwiftDocKey.offset.rawValue] as? Int64 else {
            return nil
        }
        self.offset = Int(offset)
        
        
        guard let length = dictionary[SwiftDocKey.length.rawValue] as? Int64 else {
            return nil
        }
        self.length = Int(length)

        switch kind {
        case .class,
             .struct:
            isInjectable = true

        case .enum,
             .extension:
            isInjectable = false
            
        default:
            return nil
        }

        do {
            guard let typeString = dictionary[SwiftDocKey.name.rawValue] as? String,
                  let type = try ConcreteType(typeString) else {
                return nil
            }

            if let matches = try NSRegularExpression(pattern: "(\(type.name)<.*>)").matches(in: lineString),
               let _type = try ConcreteType(matches[0]) {
                self.type = _type
            } else {
                self.type = type
            }
        } catch {
            return nil
        }
        
        hasBody = dictionary.keys.contains(SwiftDocKey.bodyOffset.rawValue)
        
        if let attributeKindString = dictionary["key.accessibility"] as? String {
            self.accessLevel = AccessLevel(attributeKindString)
        } else {
            accessLevel = .default
        }
    }
}

// MARK: - Conversion

private extension Int {
    /// Default value used until the real value gets determined later on.
    static let defaultLine = -1
}

extension SourceKitDependencyAnnotation {
    
    func toTokens() throws -> [AnyTokenBox] {
        let tokenBox: AnyTokenBox
        switch dependencyKind {
        case .registration?:
            guard let type = type else {
                throw LexerError.invalidAnnotation(FileLocation(),
                                                   underlyingError: TokenError.invalidAnnotation(annotationString))
            }
            
            let annotation = RegisterAnnotation(name: name,
                                                type: type,
                                                protocolTypes: abstractTypes)
 
            tokenBox = TokenBox(value: annotation,
                                offset: offset,
                                length: length,
                                line: .defaultLine)
        case .parameter?:
            guard let type = abstractTypes.first, abstractTypes.count == 1 else {
                throw LexerError.invalidAnnotation(FileLocation(),
                                                   underlyingError: TokenError.invalidAnnotation(annotationString))
            }
            let annotation = ParameterAnnotation(name: name, type: type.concreteType)
            tokenBox = TokenBox(value: annotation,
                                offset: offset,
                                length: length,
                                line: .defaultLine)
            
        case .reference?:
            guard abstractTypes.isEmpty == false else {
                throw LexerError.invalidAnnotation(FileLocation(),
                                                   underlyingError: TokenError.invalidAnnotation(annotationString))
            }
            let annotation = ReferenceAnnotation(name: name, types: abstractTypes)
            tokenBox = TokenBox(value: annotation,
                                offset: offset,
                                length: length,
                                line: .defaultLine)
            
        case .none:
            throw LexerError.invalidAnnotation(FileLocation(),
                                               underlyingError: TokenError.invalidAnnotation(annotationString))
        }
        
        return [tokenBox] + configurationAttributes.map { attribute in
            let annotation = ConfigurationAnnotation(attribute: attribute, target: .dependency(name: name))
            return TokenBox(value: annotation,
                            offset: offset,
                            length: length,
                            line: .defaultLine)
        }
    }
}

extension SourceKitTypeDeclaration {
    
    var toToken: AnyTokenBox {
        if isInjectable {
            let injectableType = InjectableType(type: type, accessLevel: accessLevel)
            return TokenBox(value: injectableType, offset: offset, length: length, line: .defaultLine)
        } else {
            return TokenBox(value: AnyDeclaration(), offset: offset, length: length, line: .defaultLine)
        }
    }
    
    var endToken: AnyTokenBox? {
        guard hasBody == true else {
            return nil
        }
        
        let offset = self.offset + length - 1
        if isInjectable {
            return TokenBox(value: EndOfInjectableType(), offset: offset, length: 1, line: .defaultLine)
        } else {
            return TokenBox(value: EndOfAnyDeclaration(), offset: offset, length: 1, line: .defaultLine)
        }
    }
}

private extension AccessLevel {

    init(_ stringValue: String) {
        guard let value = AccessLevel.allCases.first(where: { stringValue.contains($0.rawValue) }) else {
            self = .internal
            return
        }
        self = value
    }
}

private extension Dependency.Kind {
    
    init?(_ stringValue: String) {
        guard let value = Dependency.Kind.allCases.first(where: { stringValue.contains($0.rawValue) }) else {
            return nil
        }
        self = value
    }
}
