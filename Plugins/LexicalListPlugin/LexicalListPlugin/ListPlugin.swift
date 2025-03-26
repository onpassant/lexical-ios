/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Lexical
import UIKit

extension CommandType {
  public static let insertUnorderedList = CommandType(rawValue: "insertUnorderedList")
  public static let insertOrderedList = CommandType(rawValue: "insertOrderedList")
  public static let removeList = CommandType(rawValue: "removeList")
}

open class ListPlugin: Plugin {
  public init() {}

  weak var editor: Editor?

  public func setUp(editor: Editor) {
    self.editor = editor
    do {
      try editor.registerNode(nodeType: NodeType.list, class: ListNode.self)
      try editor.registerNode(nodeType: NodeType.listItem, class: ListItemNode.self)

      _ = editor.registerCommand(type: .insertUnorderedList, listener: { [weak editor] payload in
        guard let editor else { return false }
        try? insertList(editor: editor, listType: .bullet)
        return true
      })

      _ = editor.registerCommand(type: .insertOrderedList, listener: { [weak editor] payload in
        guard let editor else { return false }
        try? insertList(editor: editor, listType: .number)
        return true
      })

    _ = try editor.registerUpdateListener { [weak editor] activeEditorState, previousEditorState, dirtyNodes in
        guard let editor else {
            return
        }

        guard let selection = activeEditorState.selection as? RangeSelection else {
            return
        }

        guard let firstNode = try? selection.getNodes().first else {
            return
        }

        if let currentListItemNode = (firstNode is ListItemNode ? firstNode : firstNode.getParent()) as? ListItemNode {
            if let listItemAbove = currentListItemNode.getPreviousSibling() as? ListItemNode {
                let childrenAbove = listItemAbove.getChildren()
                var shouldEndList = false
                if let firstChildAbove = childrenAbove.first as? TextNode {
                    let text = firstChildAbove.getTextPart()
                    let pattern = "[\\u200B]+"
                    let regex = try! NSRegularExpression(pattern: pattern)
                    let range = NSRange(location: 0, length: text.utf16.count)
                    if text.isEmpty || regex.firstMatch(in: text, options: [], range: range) != nil {
                        shouldEndList = true
                    }
                } else if childrenAbove.isEmpty {
                    shouldEndList = true
                }

                if shouldEndList {
                    print("end")
                    try! editor.update {
                        try listItemAbove.replace(replaceWith: ParagraphNode())
                        let paragraph = ParagraphNode()
                        try paragraph.setIndent(0)
                        //try paragraph.append([TextNode(text: "")])
                        try currentListItemNode.replace(replaceWith: paragraph)

                    }
                    return
                }
            }
        }

        if let listItem = firstNode as? ListItemNode {
            if selection.anchor.offset == 0, selection.focus.offset == 0 {
                try! editor.update {
                    try listItem.append([TextNode(text: "\u{200B}")])
                }
                return
            }
        }

        guard selection.anchor.offset == 2, selection.focus.offset == 2 else {
            return
        }

        guard let node = firstNode as? TextNode else {
            return
        }

        let pattern = "[\\u200B]*[-*] [\\u200B]*"
        let regex = try! NSRegularExpression(pattern: pattern)
        let text = node.getTextPart()
        let range = NSRange(location: 0, length: text.utf16.count)

        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return
        }

        guard node.getPreviousSibling() == nil && node.getNextSibling() == nil else {
            return
        }

        try! editor.update {
            let list = createListNode(listType: .bullet)
            let listItem = ListItemNode()
            try list.append([listItem])

            try node.getParent()?.replace(replaceWith: list)
        }
    }

    try editor.registerCustomDrawing(customAttribute: .listItem, layer: .text, granularity: .singleParagraph) {
        attributeKey, attributeValue, layoutManager, characterRange, expandedCharRange, glyphRange, rect, firstLineFragment in

        guard let attributeValue = attributeValue as? ListItemAttribute, let textStorage = layoutManager.textStorage as? TextStorage else {
          return
        }

        if characterRange.location != 0 && (textStorage.string as NSString).substring(with: NSRange(location: characterRange.location - 1, length: 1)) != "\n" {
          return
        }

        let isFirstLine = (glyphRange.location == 0)

        var attributes = textStorage.attributes(at: characterRange.location, effectiveRange: nil)

        var spacingBefore = 0.0
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle, let mutableParagraphStyle = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle {
          mutableParagraphStyle.headIndent = 0
          mutableParagraphStyle.firstLineHeadIndent = 0
          mutableParagraphStyle.tailIndent = 0
          spacingBefore = isFirstLine ? 0 : paragraphStyle.paragraphSpacingBefore
          mutableParagraphStyle.paragraphSpacingBefore = 0
          attributes[.paragraphStyle] = mutableParagraphStyle
        }
        attributes.removeValue(forKey: .underlineStyle)
        attributes.removeValue(forKey: .strikethroughStyle)
        let bulletDrawRect = firstLineFragment.inset(by: UIEdgeInsets(top: spacingBefore, left: attributeValue.characterIndentationPixels, bottom: 0, right: 0))

        attributeValue.listItemCharacter.draw(in: bulletDrawRect, withAttributes: attributes)
      }
    } catch {
      print("\(error)")
    }
  }

  public func tearDown() {
  }
}
