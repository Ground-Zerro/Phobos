#ifndef _IO_URING_SUPPORT_H_
#define _IO_URING_SUPPORT_H_

#ifdef USE_IO_URING

#include <liburing.h>
#include <sys/socket.h>
#include <string.h>
#include "threading.h"

#define URING_QUEUE_DEPTH 256
#define URING_RECV_BUFFERS 64

enum uring_op_type {
    URING_OP_RECV_CLIENT = 1,
    URING_OP_RECV_SERVER = 2,
    URING_OP_SEND_CLIENT = 3,
    URING_OP_SEND_SERVER = 4,
};

typedef struct {
    uint8_t op_type;
    int fd;
    client_entry_t *client;
    uint8_t buffer[QUEUE_BUFFER_SIZE];
    struct sockaddr_in addr;
    struct msghdr msg;
    struct iovec iov;
} uring_request_t;

typedef struct {
    struct io_uring ring;
    uring_request_t recv_reqs[URING_RECV_BUFFERS];
    int initialized;
} uring_context_t;

static inline int uring_init(uring_context_t *ctx) {
    struct io_uring_params params;
    memset(&params, 0, sizeof(params));
    int ret = io_uring_queue_init_params(URING_QUEUE_DEPTH, &ctx->ring, &params);
    if (ret < 0) return ret;
    ctx->initialized = 1;
    return 0;
}

static inline void uring_cleanup(uring_context_t *ctx) {
    if (ctx->initialized) {
        io_uring_queue_exit(&ctx->ring);
        ctx->initialized = 0;
    }
}

static inline int uring_submit_recv_client(uring_context_t *ctx, int listen_sock, int req_idx) {
    uring_request_t *req = &ctx->recv_reqs[req_idx];
    req->op_type = URING_OP_RECV_CLIENT;
    req->fd = listen_sock;
    req->client = NULL;
    req->iov.iov_base = req->buffer;
    req->iov.iov_len = QUEUE_BUFFER_SIZE;
    memset(&req->msg, 0, sizeof(req->msg));
    req->msg.msg_name = &req->addr;
    req->msg.msg_namelen = sizeof(req->addr);
    req->msg.msg_iov = &req->iov;
    req->msg.msg_iovlen = 1;

    struct io_uring_sqe *sqe = io_uring_get_sqe(&ctx->ring);
    if (!sqe) return -1;
    io_uring_prep_recvmsg(sqe, listen_sock, &req->msg, 0);
    io_uring_sqe_set_data(sqe, req);
    return 0;
}

static inline int uring_submit_recv_server(uring_context_t *ctx, client_entry_t *client, int req_idx) {
    uring_request_t *req = &ctx->recv_reqs[req_idx];
    req->op_type = URING_OP_RECV_SERVER;
    req->fd = client->server_sock;
    req->client = client;
    req->iov.iov_base = req->buffer;
    req->iov.iov_len = QUEUE_BUFFER_SIZE;
    memset(&req->msg, 0, sizeof(req->msg));
    req->msg.msg_iov = &req->iov;
    req->msg.msg_iovlen = 1;

    struct io_uring_sqe *sqe = io_uring_get_sqe(&ctx->ring);
    if (!sqe) return -1;
    io_uring_prep_recvmsg(sqe, client->server_sock, &req->msg, 0);
    io_uring_sqe_set_data(sqe, req);
    return 0;
}

static inline int uring_submit_send(uring_context_t *ctx, int fd,
                                     uint8_t *data, int length,
                                     struct sockaddr_in *dest_addr) {
    struct io_uring_sqe *sqe = io_uring_get_sqe(&ctx->ring);
    if (!sqe) return -1;

    if (dest_addr) {
        static _Thread_local struct msghdr send_msg;
        static _Thread_local struct iovec send_iov;
        send_iov.iov_base = data;
        send_iov.iov_len = length;
        memset(&send_msg, 0, sizeof(send_msg));
        send_msg.msg_name = dest_addr;
        send_msg.msg_namelen = sizeof(*dest_addr);
        send_msg.msg_iov = &send_iov;
        send_msg.msg_iovlen = 1;
        io_uring_prep_sendmsg(sqe, fd, &send_msg, MSG_DONTWAIT);
    } else {
        io_uring_prep_send(sqe, fd, data, length, MSG_DONTWAIT);
    }
    io_uring_sqe_set_data(sqe, NULL);
    return 0;
}

static inline int uring_flush(uring_context_t *ctx) {
    return io_uring_submit(&ctx->ring);
}

static inline int uring_wait_cqe(uring_context_t *ctx, struct io_uring_cqe **cqe, int timeout_ms) {
    struct __kernel_timespec ts = {
        .tv_sec = timeout_ms / 1000,
        .tv_nsec = (timeout_ms % 1000) * 1000000LL
    };
    return io_uring_wait_cqe_timeout(&ctx->ring, cqe, &ts);
}

static inline void uring_cqe_seen(uring_context_t *ctx, struct io_uring_cqe *cqe) {
    io_uring_cqe_seen(&ctx->ring, cqe);
}

#endif
#endif
