const String = []const u8;

pub const JsonAny = union(enum) {
    string: String,
    boolean: bool,
    int: isize,
    float: f64,
    array: []JsonAny,
    object: std.StringHashMap(JsonAny),
};

const IntOrString = union(enum) {
    number: isize,
    string: String,
};

pub const Message = struct {
    jsonrpc: String = "2.0",
};

pub const RequestMessage = struct {
    Message: Message,

    id: IntOrString,
    method: String,
    params: ?union(enum) {
        initialize: *InitializeParams,
    },
};

pub const ResponseMessage = struct {
    Message: Message,

    id: ?IntOrString,
    result: ?union(enum) {
        initialize: *InitializeResult,
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
    message: String,
};

pub const NotificationMessage = struct {
    Message: Message,

    method: String,
    params: ?union(enum) {
        __cancelRequest: *CancelParams,
    },
};

pub const DocumentUri = String;

pub const Position = struct {
    line: isize,
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
    originSelectionRange: ?Range,
    targetUri: DocumentUri,
    targetRange: Range,
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
    code: ?IntOrString,
    source: ?String,
    message: String,
    relatedInformation: ?[]DiagnosticRelatedInformation,
};

pub const DiagnosticRelatedInformation = struct {
    location: Location,
    message: String,
};

pub const Command = struct {
    title: String,
    command: String,
    arguments: ?[]JsonAny,
};

pub const TextEdit = struct {
    range: Range,
    newText: String,
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
    kind: String = "create",
    uri: DocumentUri,
    options: ?CreateFileOptions,
};

pub const RenameFileOptions = struct {
    overwrite: ?bool,
    ignoreIfExists: ?bool,
};

pub const RenameFile = struct {
    kind: String = "rename",
    oldUri: DocumentUri,
    newUri: DocumentUri,
    options: ?RenameFileOptions,
};

pub const DeleteFileOptions = struct {
    recursive: ?bool,
    ignoreIfNotExists: ?bool,
};

pub const DeleteFile = struct {
    kind: String = "delete",
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
    languageId: String,
    version: isize,
    text: String,
};

pub const DocumentFilter = struct {
    language: ?String,
    scheme: ?String,
    pattern: ?String,
};

pub const DocumentSelector = []DocumentFilter;

pub const markup_kind = struct {
    pub const plaintext = "plaintext";
    pub const markdown = "markdown";
};

pub const MarkupContent = struct {
    kind: string,
    value: String,
};

pub const InitializeParams = struct {
    processId: ?isize,
    rootUri: ?DocumentUri,
    initializationOptions: ?JsonAny,
    capabilities: ClientCapabilities,
    trace: ?String,
    workspaceFolders: ?[]WorkspaceFolder,

    pub const trace_off = "off";
    pub const trace_messages = "messages";
    pub const trace_verbose = "verbose";
};

pub const WorkspaceClientCapabilities = struct {
    applyEdit: ?bool,
    workspaceEdit: ?struct {
        documentChanges: ?bool,
        resourceOperations: ?[]String,
        failureHandling: ?String,

        pub const resource_operation_kind_create = "create";
        pub const resource_operation_kind_rename = "rename";
        pub const resource_operation_kind_delete = "delete";
        pub const failure_handling_kind_abort = "abort";
        pub const failure_handling_kind_transactional = "transactional";
        pub const failure_handling_kind_undo = "undo";
        pub const failure_handling_kind_textOnlyTransactional = "textOnlyTransactional";
    },
    didChangeConfiguration: ?struct {
        dynamicRegistration: ?bool,
    },
    didChangeWatchedFiles: ?struct {
        dynamicRegistration: ?bool,
    },
    symbol: ?struct {
        dynamicRegistration: ?bool,
        symbolKind: ?struct {
            valueSet: ?[]SymbolKind,
        },
    },
    executeCommand: ?struct {
        dynamicRegistration: ?bool,
    },
    workspaceFolders: ?bool,
    configuration: ?bool,
};

pub const TextDocumentClientCapabilities = struct {
    synchronization: ?struct {
        dynamicRegistration: ?bool,
        willSave: ?bool,
        willSaveWaitUntil: ?bool,
        didSave: ?bool,
    },
    completion: ?struct {
        dynamicRegistration: ?bool,
        completionItem: ?struct {
            snippetSupport: ?bool,
            commitCharactersSupport: ?bool,
            documentationFormat: ?[]String,
            deprecatedSupport: ?bool,
            preselectSupport: ?bool,
        },
        completionItemKind: ?struct {
            valueSet: ?[]CompletionItemKind,
        },
        contextSupport: ?bool,
    },
    hover: ?struct {
        dynamicRegistration: ?bool,
        contentFormat: ?[]String,
    },
    signatureHelp: ?struct {
        dynamicRegistration: ?bool,
        signatureInformation: ?struct {
            documentationFormat: ?[]String,
            parameterInformation: ?struct {
                labelOffsetSupport: ?bool,
            },
        },
    },
    references: ?struct {
        dynamicRegistration: ?bool,
    },
    documentHighlight: ?struct {
        dynamicRegistration: ?bool,
    },
    documentSymbol: ?struct {
        dynamicRegistration: ?bool,
        symbolKind: ?struct {
            valueSet: ?[]SymbolKind,
        },
        hierarchicalDocumentSymbolSupport: ?bool,
    },
    formatting: ?struct {
        dynamicRegistration: ?bool,
    },
    rangeFormatting: ?struct {
        dynamicRegistration: ?bool,
    },
    onTypeFormatting: ?struct {
        dynamicRegistration: ?bool,
    },
    declaration: ?struct {
        dynamicRegistration: ?bool,
        linkSupport: ?bool,
    },
    definition: ?struct {
        dynamicRegistration: ?bool,
        linkSupport: ?bool,
    },
    typeDefinition: ?struct {
        dynamicRegistration: ?bool,
        linkSupport: ?bool,
    },
    implementation: ?struct {
        dynamicRegistration: ?bool,
        linkSupport: ?bool,
    },
    codeAction: ?struct {
        dynamicRegistration: ?bool,
        codeActionLiteralSupport: ?struct {
            codeActionKind: struct {
                valueSet: []String,
            },
        },
    },
    codeLens: ?struct {
        dynamicRegistration: ?bool,
    },
    documentLink: ?struct {
        dynamicRegistration: ?bool,
    },
    colorProvider: ?struct {
        dynamicRegistration: ?bool,
    },
    rename: ?struct {
        dynamicRegistration: ?bool,
        prepareSupport: ?bool,
    },
    publishDiagnostics: ?struct {
        relatedInformation: ?bool,
    },
    foldingRange: ?struct {
        dynamicRegistration: ?bool,
        rangeLimit: ?bool,
        lineFoldingOnly: ?bool,
    },
};

pub const code_action_kind = struct {
    pub const quickfix = "quickfix";
    pub const refactor = "refactor";
    pub const refactor_extract = "refactor.extract";
    pub const refactor_inline = "refactor.inline";
    pub const refactor_rewrite = "refactor.rewrite";
    pub const source = "source";
    pub const source_organizeImports = "source.organizeImports";
};

pub const CompletionItemKind = enum {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25,
};

pub const SymbolKind = enum {
    File = 1,
    Module = 2,
    Namespace = 3,
    Package = 4,
    Class = 5,
    Method = 6,
    Property = 7,
    Field = 8,
    Constructor = 9,
    Enum = 10,
    Interface = 11,
    Function = 12,
    Variable = 13,
    Constant = 14,
    String = 15,
    Number = 16,
    Boolean = 17,
    Array = 18,
    Object = 19,
    Key = 20,
    Null = 21,
    EnumMember = 22,
    Struct = 23,
    Event = 24,
    Operator = 25,
    TypeParameter = 26,
};

pub const ClientCapabilities = struct {
    workspace: ?WorkspaceClientCapabilities,
    textDocument: ?TextDocumentClientCapabilities,
    experimental: ?JsonAny,
};

pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
};

pub const TextDocumentSyncKind = enum {
    None = 0,
    Full = 1,
    Incremental = 2,
};

pub const CompletionOptions = struct {
    resolveProvider: ?bool,
    triggerCharacters: ?[]String,
};

pub const SignatureHelpOptions = struct {
    triggerCharacters: ?[]String,
};

pub const CodeActionOptions = struct {
    codeActionKinds: ?[]String,
};

pub const WorkspaceFolder = struct {
    uri: DocumentUri,
    name: String,
};

pub const ServerCapabilities = struct {};

pub const CancelParams = struct {
    id: IntOrString,
};

pub const TextDocumentPositionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};
