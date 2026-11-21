//! The Language Server Protocol messages the server reads and writes, of
//! what it uses. Requests are parsed with unknown fields ignored; responses
//! are written without the optional fields that are null.

pub const Position = struct { line: usize, character: usize };

pub const Range = struct { start: Position, end: Position };

pub const Diagnostic = struct {
    range: Range,
    /// 1 error, 2 warning
    severity: u8,
    /// the compiler that reported it
    source: []const u8,
    message: []const u8,
};

pub const PublishDiagnosticsParams = struct {
    uri: []const u8,
    version: ?i64 = null,
    diagnostics: []const Diagnostic,
};

/// `window/logMessage` and `window/showMessage`; `type`: 1 error, 2
/// warning, 3 info, 4 log
pub const MessageParams = struct { type: u8, message: []const u8 };

/// Full text sync (`change` 1); the text is read again on save from the
/// last change, so `includeText` is false
pub const TextDocumentSyncOptions = struct {
    openClose: bool = true,
    change: u8 = 1,
    save: struct { includeText: bool = false } = .{},
};

/// Pull diagnostics (LSP 3.17): a unit's files depend on each other
pub const DiagnosticOptions = struct {
    interFileDependencies: bool = true,
    workspaceDiagnostics: bool = false,
};

pub const ServerCapabilities = struct {
    textDocumentSync: TextDocumentSyncOptions = .{},
    /// only for a client that pulls diagnostics
    diagnosticProvider: ?DiagnosticOptions = null,
};

pub const InitializeResult = struct {
    capabilities: ServerCapabilities = .{},
    serverInfo: struct { name: []const u8, version: []const u8 },
};

/// What the server uses of the client's capabilities
pub const ClientCapabilities = struct {
    textDocument: struct {
        /// present when the client pulls diagnostics
        diagnostic: ?struct {} = null,
    } = .{},
    workspace: struct {
        didChangeWatchedFiles: struct { dynamicRegistration: bool = false } = .{},
        diagnostics: struct { refreshSupport: bool = false } = .{},
    } = .{},
};

pub const TextDocumentItem = struct {
    uri: []const u8,
    version: i64 = 0,
    text: []const u8,
};

pub const DidOpenParams = struct { textDocument: TextDocumentItem };

pub const VersionedTextDocumentIdentifier = struct { uri: []const u8, version: i64 = 0 };

pub const ContentChange = struct { text: []const u8 };

pub const DidChangeParams = struct {
    textDocument: VersionedTextDocumentIdentifier,
    contentChanges: []const ContentChange,
};

/// `didSave` and `didClose`
pub const TextDocumentParams = struct { textDocument: struct { uri: []const u8 } };

pub const DocumentDiagnosticParams = struct {
    textDocument: struct { uri: []const u8 },
    previousResultId: ?[]const u8 = null,
};

/// `type`: 1 created, 2 changed, 3 deleted
pub const FileEvent = struct { uri: []const u8, type: u8 };

pub const DidChangeWatchedFilesParams = struct { changes: []const FileEvent };

pub const Registration = struct {
    id: []const u8,
    method: []const u8,
    registerOptions: struct { watchers: []const struct { globPattern: []const u8 } },
};

pub const RegistrationParams = struct { registrations: []const Registration };

pub const ResponseError = struct { code: i64, message: []const u8 };

pub const error_codes = struct {
    pub const invalid_request = -32600;
    pub const method_not_found = -32601;
    pub const invalid_params = -32602;
    pub const server_not_initialized = -32002;
};
