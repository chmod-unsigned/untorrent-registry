-include .env

.PHONY: help key sign verify publish info config

help:
	@echo "Usage: make [key|sign|verify|publish|info|config]"

key:
	@if [ ! -f .env ]; then \
		read -p "Enter your GitHub email: " email; \
		read -p "Enter your GitHub username: " name; \
		echo "UNTORRENT_EMAIL=$$email" > .env; \
		echo "UNTORRENT_NAME=$$name" >> .env; \
	fi; \
	EMAIL=$$(grep UNTORRENT_EMAIL .env | cut -d= -f2); \
	NAME=$$(grep UNTORRENT_NAME .env | cut -d= -f2); \
	mkdir -p keys; \
	ssh-keygen -t ed25519 -f keys/untorrent -C "$$EMAIL" -N ""; \
	echo "$$EMAIL $$(awk '{print $$1, $$2}' keys/untorrent.pub)" > keys/allowed_signers; \
	git config user.email "$$EMAIL"; \
	git config user.name "$$NAME"; \
	git config user.signingkey "$$(pwd)/keys/untorrent.pub"; \
	git config gpg.format ssh; \
	git config commit.gpgsign true; \
	$(MAKE) info

sign:
	@if [ ! -f keys/untorrent ]; then echo "Error: Key not found. Run 'make key'."; exit 1; fi
	@jq -cj . registry.json > .tmp.data
	ssh-keygen -Y sign -n "untorrent" -f keys/untorrent .tmp.data
	@SIG=$$(base64 -w 0 < .tmp.data.sig); \
	jq -n --arg sig "$$SIG" --slurpfile reg .tmp.data '{signature: $$sig, registry: $$reg[0]}' > registry.signed.json
	@rm .tmp.data .tmp.data.sig
	@echo "Success: Registry signed."

verify:
	@if [ ! -f keys/allowed_signers ]; then echo "Error: allowed_signers missing."; exit 1; fi
	@if [ ! -f registry.signed.json ]; then echo "Error: registry.signed.json missing."; exit 1; fi
	$(eval SIGNER_EMAIL=$(shell awk '{print $$1}' keys/allowed_signers))
	@jq -cj .registry registry.signed.json > .tmp.v_data
	@jq -r .signature registry.signed.json | base64 -d > .tmp.v_sig
	@ssh-keygen -Y verify -f keys/allowed_signers -I "$(SIGNER_EMAIL)" -n "untorrent" -s .tmp.v_sig < .tmp.v_data; \
	RET=$$?; rm .tmp.v_data .tmp.v_sig; \
	if [ $$RET -ne 0 ]; then echo "Verification failed!"; exit 1; fi; \
	echo "Success: Signature verified for $(SIGNER_EMAIL)."

publish: sign verify
	git add registry.json registry.signed.json keys/untorrent.pub keys/allowed_signers .gitignore
	@git diff-index --quiet HEAD || git commit -m "Update registry: $$(date +'%Y-%m-%d %H:%M')"
	GIT_SSH_COMMAND="ssh -i $$(pwd)/keys/untorrent -o IdentitiesOnly=yes -F /dev/null" git push origin main

info:
	@echo "\n--- GITHUB PUBLIC KEY (Add to Settings > SSH keys) ---"
	@cat keys/untorrent.pub
	@echo "------------------------------------------------------\n"

config:
	@echo "\n--- PUBLIC KEY FOR config.js (Base64) ---"
	@awk '{print $$2}' keys/untorrent.pub | tr -d '\n'
	@echo "\n-----------------------------------------\n"
