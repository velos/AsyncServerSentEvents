//
//  SSETestData.swift
//  AsyncServerSentEvents
//
//  Created by Zac White on 10/24/24.
//

import Foundation

/// Contains test data for Server-Sent Events (SSE) validation
public enum SSETestData {

    // MARK: - Basic Events

    /// Tests simple single-line events
    public static let basicEvents = """
    data: simple event
    data:event with colon inline
    data:   event with many spaces after colon
    
    """

    /// Tests empty data fields
    public static let emptyDataFields = """
    data
    data:
    data
    
    """

    /// Tests multiple data fields that should concatenate with newlines
    public static let multipleDataFields = """
    data:first line
    data:second line
    data:third line
    
    """

    /// Tests a [DONE] at end
    public static let doneAtEnd = """
    data: {"id":"1"}

    data: {"id":"2"}

    data: {"id":"3"}

    data: [DONE]

    
    """

    // MARK: - Comments

    /// Tests various valid comment formats
    public static let comments = """
    :this is a comment
    : this is a comment with space
    :
    ::nested comment
    
    """

    /// Tests comment-only events
    public static let commentOnlyEvent = """
    :only comment
    :
    : second comment
    
    """

    // MARK: - Event IDs

    /// Tests various event ID formats
    public static let eventIds = """
    id:1
    data:event with id
    
    id: 2  
    data:event with id and space after id
    
    id
    data:event with empty id
    
    id:
    data:event with just colon id
    
    """

    // MARK: - Retry Intervals

    /// Tests retry interval specifications
    public static let retryIntervals = """
    retry:5000
    data:event with retry 5s
    
    retry:    9999    
    data:event with retry and spaces
    
    """

    // MARK: - Named Events

    /// Tests events with custom names
    public static let namedEvents = """
    event: custom-name
    data: named event
    
    event:no-space-name
    data: named event without space after colon
    
    event:
    data: event with empty name
    
    """

    // MARK: - Mixed Fields

    /// Tests events with multiple field types
    public static let mixedFields = """
    id:42
    event:update
    data:mixed field event
    :comment in middle
    data:more data
    
    """

    // MARK: - Special Characters

    /// Tests Unicode and special character handling
    public static let specialCharacters = """
    data:↑↓←→♠♣♥♦
    data:табла
    data:⚡☔☀
    
    """

    // MARK: - Whitespace Handling

    /// Tests various whitespace scenarios
    public static let whitespaceHandling = """
     data:leading space
    \tdata:leading tab
        data:many leading spaces
    
    """

    /// Tests data values with leading spaces after colon
    public static let dataLeadingSpaces = """
    data:first line
    data:  one leading space
    data:   two leading spaces
    
    """

    // MARK: - Complete Events

    /// Tests events with all possible fields
    public static let completeEvent = """
    id:final-test
    event:complete
    retry:1000
    data:first
    data:second
    data:third
    
    """

    // MARK: - Line Endings

    /// Tests various line ending scenarios
    public static let lineEndings = """
    data:no line ending at end\\
    data:with escaped line endings\\n\\
    data:more escaped stuff\\n
    
    """

    /// Tests CR, CRLF, and LF line endings
    public static let lineEndingVariants = "data:first\r\rdata:second\r\n\r\ndata:third\n\ndata:fourth\r\rdata:fifth\r\n\r\n"

    // MARK: - Edge Cases

    /// Tests multiple empty lines between events
    public static let multipleEmptyLines = """
    
    
    data:after multiple empty lines
    
    """

    /// Tests whitespace-only lines as event delimiters
    public static let whitespaceOnlyLines = """
    data:first event
         
    \t
    data:second event
    
    """

    /// Tests missing trailing blank line
    public static let noTrailingBlankLine = "data:unfinished event"

    // MARK: - Parser Resilience Tests

    /// Tests handling of invalid field names
    public static let invalidFields = """
    invalid-field:test
    
    another-field:no
    
    yet-another-field:yes
    
    """

    /// Tests unusual whitespace combinations
    public static let unusualWhitespace = """
    data:\ttab after colon
    data:     many spaces after colon
    data\t:tab before colon
       data:many spaces before field
    
    """

    /// Tests various line ending combinations
    public static let mixedLineEndings = """
    data:test\r
    
    data:test\r\n
    
    data:test\n
    
    data:test
    
    """

    /// Tests almost-valid field names
    public static let almostValidFields = """
    dataa:extra letter
    dat:too short
    eventt:misspelled
    
    """

    /// Tests Unicode whitespace characters
    public static let unicodeWhitespace = """
    data:\u{200B}zero-width space
    data:\u{3000}ideographic space
    data:　
    
    """

    /// Returns all valid test cases concatenated
    public static var allValidTests: [String] {
        return [
            basicEvents,
            emptyDataFields,
            multipleDataFields,
            comments,
            commentOnlyEvent,
            eventIds,
            retryIntervals,
            namedEvents,
            mixedFields,
            specialCharacters,
            whitespaceHandling,
            dataLeadingSpaces,
            completeEvent,
            lineEndings,
            lineEndingVariants,
            multipleEmptyLines,
            whitespaceOnlyLines,
            noTrailingBlankLine
        ]
    }

    /// Returns all parser resilience test cases concatenated
    public static var allResilienceTests: [String] {
        return [
            invalidFields,
            unusualWhitespace,
            mixedLineEndings,
            almostValidFields,
            unicodeWhitespace
        ]
    }
}
