_ = require 'underscore'
_s = require 'underscore.string'

DOMUtils =
  Mutating:
    replaceFirstListItem: (li, replaceWith) ->
      list = DOMUtils.closest(li, "ul, ol")

      if replaceWith.length is 0
        replaceWith = replaceWith.replace /\s/g, "&nbsp;"
        text = document.createElement("div")
        text.innerHTML = "<br>"
      else
        replaceWith = replaceWith.replace /\s/g, "&nbsp;"
        text = document.createElement("span")
        text.innerHTML = "#{replaceWith}"

      if list.querySelectorAll('li').length <= 1
        # Delete the whole list and replace with text
        list.parentNode.replaceChild(text, list)
      else
        # Delete the list item and prepend the text before the rest of the
        # list
        li.parentNode.removeChild(li)
        list.parentNode.insertBefore(text, list)

      child = text.childNodes[0] ? text
      index = Math.max(replaceWith.length - 1, 0)
      selection = document.getSelection()
      selection.setBaseAndExtent(child, index, child, index)

    removeEmptyNodes: (node) ->
      Array::slice.call(node.childNodes).forEach (child) ->
        if child.textContent is ''
          node.removeChild(child)
        else
          DOMUtils.Mutating.removeEmptyNodes(child)

    # Given a bunch of elements, it will go through and find all elements
    # that are adjacent to that one of the same type. For each set of
    # adjacent elements, it will put all children of those elements into
    # the first one and delete the remaining elements.
    collapseAdjacentElements: (els=[]) ->
      return if els.length is 0
      els = Array::slice.call(els)

      seenEls = []
      toMerge = []

      for el in els
        continue if el in seenEls
        adjacent = DOMUtils.collectAdjacent(el)
        seenEls = seenEls.concat(adjacent)
        continue if adjacent.length <= 1
        toMerge.push(adjacent)

      anchors = []
      for mergeSet in toMerge
        anchor = mergeSet[0]
        remaining = mergeSet[1..-1]
        for el in remaining
          while (el.childNodes.length > 0)
            anchor.appendChild(el.childNodes[0])
        DOMUtils.Mutating.removeElements(remaining)
        anchors.push(anchor)

      return anchors

    removeElements: (elements=[]) ->
      for el in elements
        try
          if el.parentNode then el.parentNode.removeChild(el)
        catch
          # This can happen if we've already removed ourselves from the
          # node or it no longer exists
          continue
      return elements

    applyTextInRange: (range, selection, newText) ->
      range.deleteContents()
      node = document.createTextNode(newText)
      range.insertNode(node)
      range.selectNode(node)
      selection.removeAllRanges()
      selection.addRange(range)

    getRangeAtAndSelectWord: (selection, index) ->
      range = selection.getRangeAt(index)

      # On Windows, right-clicking a word does not select it at the OS-level.
      if range.collapsed
        DOMUtils.Mutating.selectWordContainingRange(range)
        range = selection.getRangeAt(index)
      return range

    # This method finds the bounding points of the word that the range
    # is currently within and selects that word.
    selectWordContainingRange: (range) ->
      selection = document.getSelection()
      node = selection.focusNode
      text = node.textContent
      wordStart = _s.reverse(text.substring(0, selection.focusOffset)).search(/\s/)
      if wordStart is -1
        wordStart = 0
      else
        wordStart = selection.focusOffset - wordStart
      wordEnd = text.substring(selection.focusOffset).search(/\s/)
      if wordEnd is -1
        wordEnd = text.length
      else
        wordEnd += selection.focusOffset

      selection.removeAllRanges()
      range = new Range()
      range.setStart(node, wordStart)
      range.setEnd(node, wordEnd)
      selection.addRange(range)

    moveSelectionToIndexInAnchorNode: (selection, index) ->
      return unless selection.isCollapsed
      node = selection.anchorNode
      selection.setBaseAndExtent(node, index, node, index)

    moveSelectionToEnd: (selection) ->
      return unless selection.isCollapsed
      node = DOMUtils.findLastTextNode(selection.anchorNode)
      index = node.length
      selection.setBaseAndExtent(node, index, node, index)

  getSelectionRectFromDOM: (selection) ->
    selection ?= document.getSelection()
    node = selection.anchorNode
    if node.nodeType is Node.TEXT_NODE
      r = document.createRange()
      r.selectNodeContents(node)
      return r.getBoundingClientRect()
    else if node.nodeType is Node.ELEMENT_NODE
      return node.getBoundingClientRect()
    else
      return null

  isSelectionInTextNode: (selection) ->
    selection ?= document.getSelection()
    return false unless selection
    return selection.isCollapsed and selection.anchorNode.nodeType is Node.TEXT_NODE and selection.anchorOffset > 0

  isAtTabChar: (selection) ->
    selection ?= document.getSelection()
    if DOMUtils.isSelectionInTextNode(selection)
      return selection.anchorNode.textContent[selection.anchorOffset - 1] is "\t"
    else return false

  isAtBeginningOfDocument: (dom, selection) ->
    selection ?= document.getSelection()
    return false if not selection.isCollapsed
    return false if selection.anchorOffset > 0
    return true if dom.childNodes.length is 0
    return true if selection.anchorNode is dom
    firstChild = dom.childNodes[0]
    return selection.anchorNode is firstChild

  atStartOfList: ->
    selection = document.getSelection()
    anchor = selection.anchorNode
    return false if not selection.isCollapsed
    return true if anchor?.nodeName is "LI"
    return false if selection.anchorOffset > 0
    li = DOMUtils.closest(anchor, "li")
    return unless li
    return DOMUtils.isFirstChild(li, anchor)

  # Selectors for input types
  inputTypes: -> "input, textarea, *[contenteditable]"

  # https://developer.mozilla.org/en-US/docs/Web/API/Element/closest
  # Only Elements (not Text nodes) have the `closest` method
  closest: (node, selector) ->
    if node instanceof HTMLElement
      return node.closest(selector)
    else if node?.parentNode
      return DOMUtils.closest(node.parentNode, selector)
    else return null

  closestAtCursor: (selector) ->
    selection = document.getSelection()
    return unless selection?.isCollapsed
    return DOMUtils.closest(selection.anchorNode, selector)

  isInList: ->
    li = DOMUtils.closestAtCursor("li")
    list = DOMUtils.closestAtCursor("ul, ol")
    return li and list

  # Returns an array of all immediately adjacent nodes of a particular
  # nodeName relative to the root. Includes the root if it has the correct
  # nodeName.
  #
  # nodName is optional. if left blank it'll be the nodeName of the root
  collectAdjacent: (root, nodeName) ->
    nodeName ?= root.nodeName
    adjacent = []

    node = root
    while node.nextSibling?.nodeName is nodeName
      adjacent.push(node.nextSibling)
      node = node.nextSibling

    if root.nodeName is nodeName
      adjacent.unshift(root)

    node = root
    while node.previousSibling?.nodeName is nodeName
      adjacent.unshift(node.previousSibling)
      node = node.previousSibling

    return adjacent

  getNodeIndex: (context, nodeToFind) =>
    DOMUtils.findSimilarNodes(context, nodeToFind).indexOf nodeToFind

  # We need to break each node apart and cache since the `selection`
  # object will mutate underneath us.
  isSameSelection: (newSelection, oldSelection, context) =>
    return true if not newSelection?
    return false if not oldSelection
    return false if not newSelection.anchorNode? or not newSelection.focusNode?

    anchorIndex = DOMUtils.getNodeIndex(context, newSelection.anchorNode)
    focusIndex = DOMUtils.getNodeIndex(context, newSelection.focusNode)

    anchorEqual = newSelection.anchorNode.isEqualNode oldSelection.startNode
    anchorIndexEqual = anchorIndex is oldSelection.startNodeIndex
    focusEqual = newSelection.focusNode.isEqualNode oldSelection.endNode
    focusIndexEqual = focusIndex is oldSelection.endNodeIndex
    if not anchorEqual and not focusEqual
      # This means the newSelection is the same, but just from the opposite
      # direction. We don't care in this case, so check the reciprocal as
      # well.
      anchorEqual = newSelection.anchorNode.isEqualNode oldSelection.endNode
      anchorIndexEqual = anchorIndex is oldSelection.endNodeIndex
      focusEqual = newSelection.focusNode.isEqualNode oldSelection.startNode
      focusIndexEqual = focusIndex is oldSelection.startndNodeIndex

    anchorOffsetEqual = newSelection.anchorOffset == oldSelection.startOffset
    focusOffsetEqual = newSelection.focusOffset == oldSelection.endOffset
    if not anchorOffsetEqual and not focusOffsetEqual
      # This means the newSelection is the same, but just from the opposite
      # direction. We don't care in this case, so check the reciprocal as
      # well.
      anchorOffsetEqual = newSelection.anchorOffset == oldSelection.focusOffset
      focusOffsetEqual = newSelection.focusOffset == oldSelection.anchorOffset

    if (anchorEqual and
        anchorIndexEqual and
        anchorOffsetEqual and
        focusEqual and
        focusIndexEqual and
        focusOffsetEqual)
      return true
    else
      return false


  getRangeInScope: (scope) =>
    selection = document.getSelection()
    return null if not DOMUtils.selectionInScope(selection, scope)
    try
      range = selection.getRangeAt(0)
    catch
      console.warn "Selection is not returning a range"
      return document.createRange()
    range

  selectionInScope: (selection, scope) ->
    return false if not selection?
    return false if not scope?
    return (scope.contains(selection.anchorNode) and
            scope.contains(selection.focusNode))

  isEmptyBoundingRect: (rect) ->
    rect.top is 0 and rect.bottom is 0 and rect.left is 0 and rect.right is 0

  atEndOfContent: (selection, rootScope, containerScope) ->
    containerScope ?= rootScope
    if selection.isCollapsed

      # We need to use `lastChild` instead of `lastElementChild` because
      # we need to eventually check if the `selection.focusNode`, which is
      # usually a TEXT node, is equal to the returned `lastChild`.
      # `lastElementChild` will not return TEXT nodes.
      #
      # Unfortunately, `lastChild` can sometime return COMMENT nodes and
      # other blank TEXT nodes that we don't want to compare to.
      #
      # For example, if you have the structure:
      # <div>
      #   <p>Foo</p>
      # </div>
      #
      # The div may have 2 childNodes and 1 childElementNode. The 2nd
      # hidden childNode is a TEXT node with a data of "\n". I actually
      # want to return the <p></p>.
      #
      # However, The <p> element may have 1 childNode and 0
      # childElementNodes. In that case I DO want to return the TEXT node
      # that has the data of "foo"
      lastChild = DOMUtils.lastNonBlankChildNode(containerScope)

      # Special case for a completely empty contenteditable.
      # In this case `lastChild` will be null, but we are definitely at
      # the end of the content.
      if containerScope is rootScope
        return true if containerScope.childNodes.length is 0

      return false unless lastChild

      # NOTE: `.contains` returns true if `lastChild` is equal to
      # `selection.focusNode`
      #
      # See: http://ejohn.org/blog/comparing-document-position/
      inLastChild = lastChild.contains(selection.focusNode)

      # We should do true object identity here instead of `.isEqualNode`
      isLastChild = lastChild is selection.focusNode

      if isLastChild
        if selection.focusNode?.length
          atEndIndex = selection.focusOffset is selection.focusNode.length
        else
          atEndIndex = selection.focusOffset is 0
        return atEndIndex
      else if inLastChild
        DOMUtils.atEndOfContent(selection, rootScope, lastChild)
      else return false

    else return false

  lastNonBlankChildNode: (node) ->
    lastNode = null
    for childNode in node.childNodes by -1
      if childNode.nodeType is Node.TEXT_NODE
        if DOMUtils.isBlankTextNode(childNode)
          continue
        else
          return childNode
      else if childNode.nodeType is Node.ELEMENT_NODE
        return childNode
      else continue
    return lastNode

  findLastTextNode: (node) ->
    return null unless node
    return node if node.nodeType is Node.TEXT_NODE
    for childNode in node.childNodes by -1
      if childNode.nodeType is Node.TEXT_NODE
        return childNode
      else if childNode.nodeType is Node.ELEMENT_NODE
        return DOMUtils.findLastTextNode(childNode)
      else continue
    return null

  findFirstTextNode: (node) ->
    return null unless node
    return node if node.nodeType is Node.TEXT_NODE
    for childNode in node.childNodes
      if childNode.nodeType is Node.TEXT_NODE
        return childNode
      else if childNode.nodeType is Node.ELEMENT_NODE
        return DOMUtils.findFirstTextNode(childNode)
      else continue
    return null

  isBlankTextNode: (node) ->
    return if not node?.data
    # \u00a0 is &nbsp;
    node.data.replace(/\u00a0/g, "x").trim().length is 0

  findSimilarNodes: (context, nodeToFind) ->
    nodeList = []
    if nodeToFind.isEqualNode(context)
      nodeList.push(context)
      return nodeList
    treeWalker = document.createTreeWalker context
    while treeWalker.nextNode()
      if treeWalker.currentNode.isEqualNode nodeToFind
        nodeList.push(treeWalker.currentNode)

    return nodeList

  escapeHTMLCharacters: (text) ->
    map =
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    text.replace /[&<>"']/g, (m) -> map[m]

  # Checks to see if a particular node is visible and any of its parents
  # are visible.
  #
  # WARNING. This is a fairly expensive operation and should be used
  # sparingly.
  nodeIsVisible: (node) ->
    while node and node isnt window.document
      style = window.getComputedStyle(node)
      node = node.parentNode
      continue unless style?
      # NOTE: opacity must be soft ==
      if style.opacity is 0 or style.opacity is "0" or style.visibility is "hidden" or style.display is "none"
        return false
    return true

  # Finds all of the non blank node in a {Document} object or HTML string.
  #
  # - `elementOrHTML` a dom element or an HTML string. If passed a
  # string, it will use `DOMParser` to convert it into a DOM object.
  #
  # "Non blank" is defined as any node whose `textContent` returns a
  # whitespace string.
  #
  # It will also reject nodes we see are invisible due to basic CSS
  # properties.
  #
  # Returns an array of DOM Nodes
  nodesWithContent: (elementOrHTML) ->
    nodes = []
    if _.isString(elementOrHTML)
      domParser = new DOMParser()
      doc = domParser.parseFromString(elementOrHTML, "text/html")
      allNodes = doc.body.childNodes
    else if elementOrHTML?.childNodes
      allNodes = elementOrHTML.childNodes
    else return nodes

    # We need to check `childNodes` instead of `children` to look for
    # plain Text nodes.
    for node in allNodes by -1
      if node.nodeName is "IMG"
        nodes.unshift node

      # It's important to use `textContent` and NOT `innerText`.
      # `innerText` causes a full reflow on every call because it
      # calcaultes CSS styles to determine if the text is truly visible or
      # not. This utility method must NOT cause a reflow. We instead will
      # check for basic cases ourselves.
      if (node.textContent ? "").trim().length is 0
        continue

      if node.style?.opacity is 0 or node.style?.opacity is "0" or node.style?.visibility is "hidden" or node.style?.display is "none"
        continue

      nodes.unshift node

    # No nodes with content found!
    return nodes

  parents: (node) ->
    nodes = []
    nodes.unshift(node) while node = node.parentNode
    return nodes

  # Returns true if the node is the first child of the root, is the root,
  # or is the first child of the first child of the root, etc.
  isFirstChild: (root, node) ->
    return false unless root and node
    return true if root is node
    return false unless root.childNodes[0]
    return true if root.childNodes[0] is node
    return DOMUtils.isFirstChild(root.childNodes[0], node)

  commonAncestor: (nodes=[]) ->
    nodes = Array::slice.call(nodes)

    minDepth = Number.MAX_VALUE
    # Sometimes we can potentially have tons of REALLY deeply nested
    # nodes. Since we're looking for a common ancestor we can really speed
    # this up by keeping track of the min depth reached. We know that we
    # won't need to check past that.
    parents = ->
      nodes = []
      depth = 0
      while node = node.parentNode
        nodes.unshift(node)
        depth += 1
        if depth > minDepth then break
      minDepth = Math.min(minDepth, depth)
      return nodes

    # _.intersection will preserve the ordering of the parent node arrays.
    # parents are ordered top to bottom, so the last node is the most
    # specific common ancenstor
    _.last(_.intersection.apply(null, nodes.map(DOMUtils.parents)))

  scrollAdjustmentToMakeNodeVisibleInContainer: (node, container) ->
    return unless node
    nodeRect = node.getBoundingClientRect()
    containerRect = container.getBoundingClientRect()
    return @scrollAdjustmentToMakeRectVisibleInRect(nodeRect, containerRect)

  scrollAdjustmentToMakeRectVisibleInRect: (nodeRect, containerRect) ->
    distanceBelowBottom = (nodeRect.top + nodeRect.height) - (containerRect.top + containerRect.height)
    if distanceBelowBottom >= 0
      return distanceBelowBottom

    distanceAboveTop = containerRect.top - nodeRect.top
    if distanceAboveTop >= 0
      return -distanceAboveTop

    return 0

module.exports = DOMUtils
