import NIO
import NIOHTTP1

/// A type that can respond to HTTP requests.
protocol HTTPRouter {
    /// Handle a `Request` with a future containing a `Response`. Should never result in an error.
    ///
    /// - Parameter request: The request to respond to.
    /// - Returns: A future containing the response to send to the
    ///   client.
    func handle(request: Request) -> EventLoopFuture<Response>
}

/// Responds to incoming `HTTPRequests` with an `Response` generated
/// by the `HTTPRouter`.
final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
  
    // Indicates that the TCP connection needs to be closed after a
    // response has been sent.
    private var keepAlive = true
  
    /// A temporary local Request that is used to accumulate data
    /// into.
    private var request: Request?
  
    /// The responder to all requests.
    private let router: HTTPRouter
    
    /// Initialize with a responder to handle all requests.
    ///
    /// - Parameter responder: The object to respond to all incoming
    ///   `Request`s.
    init(router: HTTPRouter) {
        self.router = router
    }
  
    /// Received incoming `InboundIn` data, writing a response based
    /// on the `Responder`.
    ///
    /// - Parameters:
    ///   - context: The context of the handler.
    ///   - data: The inbound data received.
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
    
        switch part {
        case .head(let requestHead):
            // If the part is a `head`, a new Request is received
            keepAlive = requestHead.isKeepAlive
      
            let contentLength: Int
      
            // We need to check the content length to reserve memory
            // for the body
            if let length = requestHead.headers["content-length"].first {
                contentLength = Int(length) ?? 0
            } else {
                contentLength = 0
            }
      
            let body: ByteBuffer?
      
            // Allocates the memory for accumulation
            if contentLength > 0 {
                body = context.channel.allocator.buffer(capacity: contentLength)
            } else {
                body = nil
            }
      
            self.request = Request(
                head: requestHead,
                bodyBuffer: body
            )
        case .body(var newData):
            // Appends new data to the already reserved buffer
            self.request?.bodyBuffer?.writeBuffer(&newData)
        case .end:
            guard let request = request else { return }
      
            // Responds to the request
            let response = router.handle(request: request)
                // Ensure we're on the right ELF or NIO will assert.
                .hop(to: context.eventLoop)
            self.request = nil
      
            // Writes the response when done
            self.writeResponse(version: request.head.version, response: response, to: context)
        }
    }
  
    /// Writes the `Responder`'s `Response` to a
    /// `ChannelHandlerContext`.
    ///
    /// - Parameters:
    ///   - version: The HTTP version of the connection.
    ///   - response: The reponse to write to the handler context.
    ///   - context: The context to write to.
    /// - Returns: An future that completes when the response is
    ///   written.
    @discardableResult
    private func writeResponse(version: HTTPVersion, response: EventLoopFuture<Response>, to context: ChannelHandlerContext) -> EventLoopFuture<Void> {
        return response.flatMap { response in
            let responseWriter = HTTPResponseWriter(version: version, handler: self, context: context)
            responseWriter.completionPromise.futureResult.whenComplete { _ in
                if !self.keepAlive {
                    context.close(promise: nil)
                }
            }
            
            response.write(to: responseWriter)
            return responseWriter.completionPromise.futureResult
        }
    }
    
    /// Handler for when the channel read is complete.
    ///
    /// - Parameter context: the context to send events to.
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
}

/// Used for writing a response to a remote peer with an
/// `HTTPHandler`.
private struct HTTPResponseWriter: ResponseWriter {
    /// A promise to hook into for when the writing is finished.
    let completionPromise: EventLoopPromise<Void>

    /// The HTTP version we're working with.
    private var version: HTTPVersion
    
    /// The handler in which this writer is writing.
    private let handler: HTTPHandler
    
    /// The context that should be written to.
    private let context: ChannelHandlerContext
    
    /// Initialize
    /// - Parameters:
    ///   - version: The HTTPVersion of this connection.
    ///   - handler: The handler in which this response is writing
    ///     inside.
    ///   - context: The context to write responses to.
    init(version: HTTPVersion, handler: HTTPHandler, context: ChannelHandlerContext) {
        self.version = version
        self.handler = handler
        self.context = context
        self.completionPromise = context.eventLoop.makePromise()
    }
    
    // MARK: ResponseWriter
    
    func writeHead(status: HTTPResponseStatus, _ headers: HTTPHeaders) {
        let head = HTTPResponseHead(version: version, status: status, headers: headers)
        context.write(handler.wrapOutboundOut(.head(head)), promise: nil)
    }
    
    func writeBody(_ body: ByteBuffer) {
        context.writeAndFlush(handler.wrapOutboundOut(.body(IOData.byteBuffer(body))), promise: nil)
    }
    
    func writeEnd() {
        context.writeAndFlush(handler.wrapOutboundOut(.end(nil)), promise: completionPromise)
    }
}
