#ifndef _MASKING_STUN_H_
#define _MASKING_STUN_H_

#include <stdint.h>
#include <netinet/in.h>
#include "wg-obfuscator.h"
#include "masking.h"

static const uint8_t COOKIE_BE[4] = {0x21,0x12,0xA4,0x42};
#define STUN_TYPE_DATA_IND      0x0115
#define STUN_BINDING_REQ        0x0001
#define STUN_BINDING_RESP       0x0101
#define STUN_ATTR_XORMAPPED     0x0020
#define STUN_ATTR_SOFTWARE      0x8022
#define STUN_ATTR_FINGERPR      0x8028
#define STUN_ATTR_DATA          0x0013

extern masking_handler_t stun_masking_handler;

int stun_check_magic(const uint8_t *buf, size_t len);

void stun_on_handshake_req(obfuscator_config_t *config,
                                client_entry_t *client,
                                direction_t direction,
                                const struct sockaddr_in *src_addr,
                                const struct sockaddr_in *dest_addr,
                                send_data_callback_t send_back_callback,
                                send_data_callback_t send_forward_callback);

void stun_on_timer(obfuscator_config_t *config,
                                client_entry_t *client,
                                const struct sockaddr_in *client_addr,
                                const struct sockaddr_in *server_addr,
                                send_data_callback_t send_to_client_callback,
                                send_data_callback_t send_to_server_callback);

int stun_on_data_unwrap(uint8_t *buffer, int length,
                                obfuscator_config_t *config,
                                client_entry_t *client,
                                direction_t direction,
                                const struct sockaddr_in *src_addr,
                                const struct sockaddr_in *dest_addr,
                                send_data_callback_t send_back_callback,
                                send_data_callback_t send_forward_callback);

#endif // _MASKING_STUN_H_
