const string = []const u8;

const numberOrString = union(enum) {
    number: isize,
    string: string,
};

pub const Message = struct {
    jsonrpc: string = "2.0",
};

pub const RequestMessage = struct {
    Message: Message,

    id: numberOrString,
    method: string,
    params: ?union(enum) {
        initialize: *InitializeParams,
    },
};

pub const ResponseMessage = struct {
    Message: Message,

    id: ?numberOrString,
    result: ?union(enum) {
        number: f64,
        string: string,
        boolean: bool,
    },
    err: ?ResponseError,
};

pub const ResponseError = struct {
    code: enum {
        parseError = -32700,
        invalidRequest = -32600,
        methodNotFound = -32601,
        invalidParams = -32602,
        internalError = -32603,
        serverErrorStart = -32099,
        serverErrorEnd = -32000,
        serverNotInitialized = -32002,
        unknownErrorCode = -32001,

        requestCancelled = -32800,
        contentModified = -32801,
    },
    message: string,
};

pub const NotificationMessage = struct {
    Message: Message,

    method: string,
    params: ?union(enum) {
        __cancelRequest: *CancelParams,
    },
};

pub const DocumentUri = string;

pub const Position = struct {
    /// Line position in a document (zero-based).
    line: isize,

    /// Character offset on a line in a document (zero-based).
    character: isize,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Location = struct {
    uri: DocumentUri,
    range: Range,
};

pub const LocationLink = struct {
    /// Span of the origin of this link.
    ///
    /// Used as the underlined span for mouse interaction. Defaults to the word range at
    /// the mouse position.
    originSelectionRange: ?Range,

    /// The target resource identifier of this link.
    targetUri: DocumentUri,

    /// The full target range of this link. If the target for example is a symbol then target range is the
    /// range enclosing this symbol not including leading/trailing whitespace but everything else
    /// like comments. This information is typically used to highlight the range in the editor.
    targetRange: Range,

    /// The range that should be selected and revealed when this link is being followed, e.g the name of a function.
    /// Must be contained by the the `targetRange`. See also `DocumentSymbol#range`
    targetSelectionRange: Range,
};

pub const Diagnostic = struct {
    range: Range,
    severity: ?enum {
        err = 1,
        warning = 2,
        information = 3,
        hint = 4,
    },
    code: ?numberOrString,
    source: ?string,
    message: string,
    relatedInformation: ?[]DiagnosticRelatedInformation,
};

pub const DiagnosticRelatedInformation = struct {
    location: Location,
    message: string,
};

pub const Command = struct {
    title: string,
    command: string,
    arguments: ?[]void,
};

pub const TextEdit = struct {
    range: Range,
    newText: string,
};

pub const TextDocumentEdit = struct {
    textDocument: VersionedTextDocumentIdentifier,
    edits: []TextEdit,
};

pub const VersionedTextDocumentIdentifier = struct {
    TextDocumentIdentifier: TextDocumentIdentifier,
    version: ?isize,
};

pub const TextDocumentIdentifier = struct {
    uri: DocumentUri,
};

pub const CreateFileOptions = struct {
    overwrite: ?bool,
    ignoreIfExists: ?bool,
};

pub const CreateFile = struct {
    kind: string = "create",
    uri: DocumentUri,
    options: ?CreateFileOptions,
};

pub const RenameFileOptions = struct {
    overwrite: ?bool,
    ignoreIfExists: ?bool,
};

pub const RenameFile = struct {
    kind: string = "rename",
    oldUri: DocumentUri,
    newUri: DocumentUri,
    options: ?RenameFileOptions,
};

pub const DeleteFileOptions = struct {
    recursive: ?bool,
    ignoreIfNotExists: ?bool,
};

pub const DeleteFile = struct {
    kind: string = "delete",
    uri: DocumentUri,
    options: ?DeleteFileOptions,
};

pub const WorkspaceEdit = struct {
    changes: ?std.AutoHashMap(DocumentUri, []TextEdit),
    documentChanges: ?[]union(enum) {
        kind__of__rename: RenameFile,
        kind__of__delete: DeleteFile,
        kind__of__create: CreateFile,
        kind__of__else: TextDocumentEdit,
    },
};

pub const TextDocumentItem = struct {
    uri: DocumentUri,
    languageId: string,
    version: isize,
    text: string,
};

pub const DocumentFilter = struct {
    language: ?string,
    scheme: ?string,
    pattern: ?string,
};

pub const DocumentSelector = []DocumentFilter;

pub const MarkupKind = enum {
    plaintext,
    markdown,
};

pub const MarkupContent = struct {
    kind: MarkupKind,
    value: string,
};

pub const InitializeParams = struct {
    processId: ?isize,
    rootUri: ?DocumentUri,
    capabilities: ClientCapabilities,
    trace: ?enum {
        off,
        messages,
        verbose,
    },
    workspaceFolders: ?[]WorkspaceFolder,
};

pub const ResourceOperationKind = enum {};

pub const CancelParams = struct {
    id: numberOrString,
};

pub const TextDocumentPositionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};
