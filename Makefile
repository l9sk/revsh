########################################################################################################################
#
# This Makefile assumes the following command line utilities are in its PATH:
#		openssl
#		grep
#		sed
#		xargs
#		base64
#		echo
#		tr
#		xxd
#		wc
#
########################################################################################################################
#
# In order to build a new binary with files generated by a previous build, just copy the contents of the old keys dir
# into the keys dir in the build directory and run make.
#
########################################################################################################################


KEY_BITS = 2048

CC = /usr/bin/gcc
CFLAGS = -std=gnu99 -Wall -Wextra -pedantic -Os
LIBS = -lssl

OBJS = revsh_io.o string_to_vector.o broker.o

KEYS_DIR = keys


all: revsh

# If you're new to Makefiles, I'm pretty much just embedding a shell script inline here.
# The goal is to call the openssl commandline tool to generate the key / cert pairs we will need,
# then convert them on the fly into c code. That c code is then #include'ed into the program we are
# compiling.
#
# This allows us to generate unique crypto per build, without too much extra overhead. (e.g. autoconf)

revsh: revsh.c remote_io_helper.h common.h config.h $(OBJS)
	if [ ! -e $(KEYS_DIR) ]; then \
		mkdir $(KEYS_DIR) ; \
	fi
	if [ ! -e $(KEYS_DIR)/dh_params_$(KEY_BITS).c ]; then \
		openssl dhparam -C $(KEY_BITS) -noout >$(KEYS_DIR)/dh_params_$(KEY_BITS).c ; \
	fi
	if [ ! -e $(KEYS_DIR)/controller_key.pem ]; then \
		(openssl req -batch -newkey rsa:$(KEY_BITS) -nodes -x509 -days 2147483647 -keyout $(KEYS_DIR)/controller_key.pem -out $(KEYS_DIR)/controller_cert.pem) && \
		(echo -n 'char *controller_fingerprint_str = "' >$(KEYS_DIR)/controller_fingerprint.c) && \
		(openssl x509 -in $(KEYS_DIR)/controller_cert.pem -fingerprint -sha1 -noout | \
			sed 's/.*=//' | \
			sed 's/://g' | \
			tr '[:upper:]' '[:lower:]' | \
			sed 's/,\s\+/,/g' | \
			sed 's/{ /{\n/' | \
			sed 's/}/\n}/' | \
			sed 's/\(\(0x..,\)\{16\}\)/\1\n/g' | \
			xargs echo -n >>$(KEYS_DIR)/controller_fingerprint.c) && \
		(echo '";' >>$(KEYS_DIR)/controller_fingerprint.c) ; \
	fi
	if [ ! -e $(KEYS_DIR)/target_key.pem ]; then \
		(openssl req -batch -newkey rsa:$(KEY_BITS) -nodes -x509 -days 2147483647 -keyout $(KEYS_DIR)/target_key.pem -out $(KEYS_DIR)/target_cert.pem) && \
		(openssl x509 -in $(KEYS_DIR)/target_cert.pem -C -noout | \
			sed 's/XXX_/target_/g' | \
			xargs | \
			sed 's/.*; \(unsigned char target_certificate\)/\1/'  >$(KEYS_DIR)/target_cert.c) && \
		(echo -n 'unsigned char target_private_key[' >$(KEYS_DIR)/target_key.c) && \
		(cat $(KEYS_DIR)/target_key.pem | \
			grep -v '^-----BEGIN RSA PRIVATE KEY-----$$' | \
			grep -v '^-----END RSA PRIVATE KEY-----$$' | \
			base64 -d | \
			xxd -p | \
			xargs echo -n | \
			sed 's/\s//g' | \
			sed 's/\(..\)/\1\n/g' | \
			wc -l | \
			xargs echo -n >>$(KEYS_DIR)/target_key.c) && \
		(echo ']={') >>$(KEYS_DIR)/target_key.c && \
		(cat $(KEYS_DIR)/target_key.pem | \
			grep -v '^-----BEGIN RSA PRIVATE KEY-----$$' | \
			grep -v '^-----END RSA PRIVATE KEY-----$$' | \
			base64 -d | \
			xxd -p | \
			xargs echo -n | \
			sed 's/\s//g' | \
			tr '[:lower:]' '[:upper:]' | \
			sed 's/\(.\{32\}\)/\1\n/g' | \
			sed 's/\(..\)/0x\1,/g' >>$(KEYS_DIR)/target_key.c) && \
		(echo '\n};' >>$(KEYS_DIR)/target_key.c) ; \
	fi
	$(CC) $(LIBS) $(CFLAGS) $(OBJS) -o revsh revsh.c

revsh_io: revsh_io.c remote_io_helper.h common.h config.h
	$(CC) $(LIBS) $(CFLAGS) -c -o revsh_io.o revsh_io.c

string_to_vector: string_to_vector.c string_to_vector.h common.h config.h
	$(CC) $(CFLAGS) -c -o string_to_vector.o string_to_vector.c

broker: broker.c common.h config.h
	$(CC) $(CFLAGS) -c -o broker.o broker.c

install:
	if [ ! -e $(HOME)/.revsh ]; then \
		mkdir $(HOME)/.revsh ; \
	fi
	if [ -e $(HOME)/.revsh/$(KEYS_DIR) ]; then \
		echo "\nERROR: $(HOME)/.revsh/$(KEYS_DIR) already exists! Move it safely out of the way then try again, please." ; \
	else \
		cp -r $(KEYS_DIR) $(HOME)/.revsh ; \
		cp revsh $(HOME)/.revsh/$(KEYS_DIR) ; \
		if [ ! -e $(HOME)/.revsh/revsh ]; then \
			ln -s $(HOME)/.revsh/$(KEYS_DIR)/revsh $(HOME)/.revsh/revsh ; \
		fi \
	fi

# make clean will remove everything. Because dh_params_2048.c will take awhile to recreate, I've added
# a make dirty line which will remove everything except the dh_params_2048.c file. This was quite useful
# during dev. This makes a rebuild with new key / cert pairs go pretty quick.
dirty:
	rm revsh $(KEYS_DIR)/target* $(KEYS_DIR)/controller* $(OBJS)

clean:
	rm revsh $(KEYS_DIR)/* $(OBJS)
	rmdir $(KEYS_DIR)
