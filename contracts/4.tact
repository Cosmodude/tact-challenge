import "@stdlib/deploy";

/*
  TASK 4 - NFT locker
  Implement a smart contract that will lock NFT for a period of time specified by the owner.
  Smart conrtact should contain logic to process following messages and getters: 

  Messages: 
  * OwnershipAssigned
   - Recives nft + time (in a forwardPayload message as uint32) for which this nft will be locked + address of the sender of the nft (prevOwner).
   - If the smart contract already holds an nft then return the incoming nft back to the sender
  * NftWithdrawal
   - Request withdrawal of the locked nft
   - If sender is not the owner (that came from OwnershipAssigned as prevOwner address) then throw "Invalid sender" 
   - If time has not passed then send message back to the sender with the comment "NFT is still locked" according to the TON's "message with text comment" standard 
   - Otherwise (all good) send the locked nft back to the owner with all the remaining TON balance
   Note that the order of checks is important
   (in case: "sender is not the owner" and "time has not passed" at the same time, "Invalid sender" error takes priority)

  Getters:
  * time
   - get how much lock time is left
  * nft
   - get the address of the locked nft 
  * owner
   - get the owner of the locked nft (that came from OwnershipAssigned as prevOwner)
*/

message(0x05138d91) OwnershipAssigned {
    queryId: Int as uint64;
    prevOwner: Address;
    forwardPayload: Slice as remaining; 
}

message(0x5fcc3d14) Transfer { 
    queryId: Int as uint64;            
    newOwner: Address; 
    responseDestination: Address; 
    customPayload: Cell?; 
    forwardAmount: Int as coins; 
    forwardPayload: Slice as remaining; 
}

message NftWithdrawal {
  queryId: Int as uint64;
  nftAddress: Address;
}

contract Task4 with Deployable {
  seed: Int as uint128;
  //nftStored: Bool = false;
  nftAddress: Address? = null; 
  ownerAddress: Address? = null;
  lockEnd: Int as uint32 = 0;
  
  init(seed: Int) {
    self.seed = seed; // needed to deploy multiple smart contracts copies from one admin address
  }

  receive(msg: OwnershipAssigned) {
    if(self.nftAddress != null){
      let body: Transfer = Transfer{ 
        queryId: msg.queryId,         
        newOwner: msg.prevOwner,
        responseDestination: msg.prevOwner,
        customPayload: null,
        forwardAmount: 0,
        forwardPayload: emptySlice()
      };

      send(SendParameters{
            to: context().sender,
            value: 0,
            mode: SendRemainingValue + SendIgnoreErrors,
            body: body.toCell()
      });
      return;
    }

    self.nftAddress = context().sender;
    self.ownerAddress = msg.prevOwner;
    self.lockEnd = msg.forwardPayload.loadUint(32) + now();
    //self.nftStored = true;
  }

  receive(msg: NftWithdrawal) {
    require(context().sender == self.ownerAddress, "Invalid sender");
    
    if(now() < self.lockEnd){
      //self.reply("NFT is still locked".asComment());
      send(SendParameters{
              to: context().sender,
              value: 0,
              mode: SendRemainingValue + SendIgnoreErrors, 
              body: "NFT is still locked".asComment()
      });
    return;
    }

    require(msg.nftAddress == self.nftAddress, "Wrong address");

    let body: Transfer = Transfer{ 
        queryId: msg.queryId,         
        newOwner: context().sender,
        responseDestination: context().sender,
        customPayload: null,  
        forwardAmount: myBalance() - context().value,
        forwardPayload: emptySlice()
    };

    send(SendParameters{
              to: self.nftAddress!!,
              value: 0,
              mode: SendRemainingBalance + SendIgnoreErrors, 
              body: body.toCell()
     });

    self.nftAddress = null;
    self.ownerAddress = null;
    //self.nftStored = false;
  }

  get fun time(): Int {
    if(self.nftAddress == null){
      return 0;
    }
    return self.lockEnd - now();
  }

  get fun nft(): Address? {
    return self.nftAddress;
  }

  get fun owner(): Address? {
    return self.ownerAddress;
  }
}