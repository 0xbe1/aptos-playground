module playground::ctoken {
    use std::signer;
    use std::string::String;

    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, MintRef, TransferRef, BurnRef};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    use playground::coin_v2;

    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use std::string;

    const ERR_CTOKEN_UNAUTHORIZED: u64 = 1;

    struct AdminRefs has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef
    }

    public fun initialize(
        account: &signer,
        object_seed: vector<u8>,
        name: String,
        symbol: String,
        decimals: u8
    ): Object<Metadata> {
        let (metadata_object_signer, mint_ref, transfer_ref, burn_ref, metadata) = coin_v2::initialize(
            account,
            object_seed,
            name,
            symbol,
            decimals
        );
        move_to(&metadata_object_signer, AdminRefs {
            mint_ref,
            transfer_ref,
            burn_ref
        });
        metadata
    }

    // admin functions

    public fun mint(admin: &signer, asset: Object<Metadata>, amount: u64): FungibleAsset acquires AdminRefs {
        let mint_ref = &borrow_admin_refs(admin, asset).mint_ref;
        fungible_asset::mint(mint_ref, amount)
    }

    public fun burn(admin: &signer, asset: Object<Metadata>, fa: FungibleAsset) acquires AdminRefs {
        let burn_ref = &borrow_admin_refs(admin, asset).burn_ref;
        fungible_asset::burn(burn_ref, fa)
    }

    public fun admin_deposit(
        admin: &signer,
        asset: Object<Metadata>,
        to: address,
        fa: FungibleAsset
    ) acquires AdminRefs {
        let transfer_ref = &borrow_admin_refs(admin, asset).transfer_ref;
        let store = primary_fungible_store ::ensure_primary_store_exists(to, asset);
        fungible_asset::deposit_with_ref(transfer_ref, store, fa)
    }

    public fun admin_withdraw(
        admin: &signer,
        asset: Object<Metadata>,
        from: address,
        amount: u64
    ): FungibleAsset acquires AdminRefs {
        let transfer_ref = &borrow_admin_refs(admin, asset).transfer_ref;
        let store = primary_fungible_store::ensure_primary_store_exists(from, asset);
        fungible_asset::withdraw_with_ref(transfer_ref, store, amount)
    }

    public fun admin_transfer(
        admin: &signer,
        asset: Object<Metadata>,
        from: address,
        to: address,
        amount: u64
    ) acquires AdminRefs {
        let fa = admin_withdraw(admin, asset, from, amount);
        admin_deposit(admin, asset, to, fa)
    }

    // helpers

    inline fun borrow_admin_refs(
        owner: &signer,
        asset: Object<Metadata>,
    ): &AdminRefs acquires AdminRefs {
        assert!(object::is_owner(asset, signer::address_of(owner)), ERR_CTOKEN_UNAUTHORIZED);
        borrow_global<AdminRefs>(object::object_address(&asset))
    }

    inline fun borrow_transfer_ref(asset: Object<Metadata>): &TransferRef {
        &borrow_global<AdminRefs>(object::object_address(&asset)).transfer_ref
    }

    #[test]
    fun admin_e2e_ok() acquires AdminRefs {
        let issuer = account::create_account_for_test(@0xBEEF);
        let alice = account::create_account_for_test(@0xA);
        let bob = account::create_account_for_test(@0xB);

        let metadata = initialize(
            &issuer,
            b"TC",
            string::utf8(b"Test Coin"),
            string::utf8(b"TC"),
            8
        );

        let fa = mint(&issuer, metadata, 10000);
        admin_deposit(&issuer, metadata, signer::address_of(&alice), fa);
        assert!(primary_fungible_store::balance(signer::address_of(&alice), metadata) == 10000, 0);

        // transfer funds from alice to bob without alice's signature!
        admin_transfer(&issuer, metadata, signer::address_of(&alice), signer::address_of(&bob), 10000);
        assert!(primary_fungible_store::balance(signer::address_of(&bob), metadata) == 10000, 0);

        let fa = admin_withdraw(&issuer, metadata, signer::address_of(&bob), 10000);
        assert!(fungible_asset::amount(&fa) == 10000, 0);

        burn(&issuer, metadata, fa);
    }
}
