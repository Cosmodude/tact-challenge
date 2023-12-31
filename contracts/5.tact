import "@stdlib/deploy";

/*
  TASK 5 - NFT random swap 
  The smart contract contains a bunch of different NFTs.
  A user brings his NFT (sends it to the smart contract), with 2.1 TON (2 for admin's profit, 0.1 for gas) in attachment (as fee for swap).
  The smart contract randomly chooses some NFT from the available NFTs (including the newly incoming one) and gives it to the user in exchange for the brought NFT (but occasionally just returns user's NFT in some cases).
  Admin can deposit NFTs without swap logic. Any NFT received from the admin is considered deposited. Admin can't swap.
  Admin can withdraw all NFTs at once, and also all TONs collected from users as fees.
  Implement getter that will return NFT addresses held by the smart contract.
  Implement getter that will return the amount of admin`s profit collected.

  In details, the smart contract (later: SC) should have this logic:
  Messages
  * AdminWithdrawalProfit 
   - SC should check that sender is the admin / otherwise throw "Insufficient privelegies"
   - SC should send all collected fees to admin except 0.1 TON (use AdminFetchProfit message as body)
     In other words: after each such operation, the contract's balance should be equal to 0.1 TON (which are reserved for storage) and the rest should be sent to the admin
  * AdminWithdrawalAllNFTs
   - SC should check that incoming tx TON value is enough for NFT withdrawal. Specifically, at least: (1 + totalNftsHeld * 0.08) TONs. Otherwise throw "Insufficent funds"
   - SC should check that sender is the admin, throw "Invalid sender" otherwise
   - If all checks pass, SC should send NFTs one by one to the admin 
   - SC should be able to withdraw all NFTs by a single message from admin
  * OwnershipAssigned 
   - if prevOwner is the owner's (admin) address, then add NFT to the collection
   - if value of TON attached is less then 2.1 TON then stop execution and return NFT back,
     but only in case that TON attached is enough to process refund without losing TONs on the SC's balance
   - randomly select NFT to send from all the NFTs that smart contract has
   - send the selected NFT to the sender with all remaining balance (except for admin profit = fees collected from this and other swaps)
     In other words: the contract's balance should increase by exactly 2 TON, some incoming TONs will be consumed for gas and the remainings of the incoming TONs should be refunded to the sender
  
  Getters
  * profit
   - returns how much collected fees is available to withdraw for the admin (all fees minus 0.1 TON)
  * nfts
   - returns dict of held NFTs with NFT indexes (sequential numbers from 0, 1, 2 ... and up to 'totalNftsHeld-1') as keys and NFT address as values 
     the order of NFTs in this dictionary doesn't matter
*/

message AdminWithdrawalProfit {
  queryId: Int as uint64;
}

message AdminWithdrawalAllNFTs {
  queryId: Int as uint64;
}

message AdminFetchProfit {
  queryId: Int as uint64;
}

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

contract Task5 with Deployable {
  seed: Int as uint128;
  owner: Address;
  profit: Int as coins = 0;
  nftCounter: Int as uint16 = 0;
  nfts: map<Int as uint16, Address>;
  
  init(seed: Int, owner: Address) {
    self.owner = owner;
    self.seed = seed; // needed to deploy multiple smart contracts copies from one admin address
  }

  receive(msg: OwnershipAssigned) {
    if(msg.prevOwner == self.owner){
      self.nfts.set(self.nftCounter, context().sender);
      self.nftCounter = self.nftCounter + 1;
      return;
    }

    // not enough Ton
    if(context().value < ton("2.1")){
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

    // enough Ton

    self.profit = self.profit + ton("2");
    let random: Int = random(0, self.nftCounter);
    nativeReserve(self.profit, 0);

    let body: Transfer = Transfer{
      queryId: msg.queryId,         
      newOwner: msg.prevOwner,
      responseDestination: msg.prevOwner,
      customPayload: null,
      forwardAmount: 0,
      forwardPayload: emptySlice()
    };

    if(random == self.nftCounter){
      send(SendParameters{
            to: context().sender,
            value: 0,
            //value: context().value - ton("2"),
            mode: SendIgnoreErrors + SendRemainingBalance,
            body: body.toCell()
      });
      return;
    }

    let sentNft: Address = self.nfts.get(random)!!;
    
    send(SendParameters{
          to: sentNft,
          //value: context().value - self.profit,
          value: 0,
          mode: SendIgnoreErrors + SendRemainingBalance,
          body: body.toCell()
    });

    self.nfts.set(random, sender());
  }

  receive(msg: AdminWithdrawalProfit) {
    require(context().sender == self.owner, "Insufficient priveleges");
    require(myBalance() >= ton("0.1"), "Nothing to withdraw");
    let body: AdminFetchProfit = AdminFetchProfit{
      queryId: msg.queryId
    };

    //nativeReserve(ton("0.1"), 0);

    send(SendParameters{
          to: self.owner,
          //value: myBalance() - ton("0.1") - context().value,
          value: myBalance() - ton("0.1"),
          mode: SendIgnoreErrors + SendRemainingValue,
          body: body.toCell()
    });

    self.profit = ton("0.1");
  }

  receive(msg: AdminWithdrawalAllNFTs) {
    require(context().sender == self.owner || sender() == myAddress(), "Invalid sender");
    require(context().value >= (ton("1") + (self.nftCounter * ton("0.08"))), "Insufficient funds");
    require(self.nftCounter > 0, "There are no nfts!");
    nativeReserve(self.profit, 0);

    let i: Int = self.nftCounter - 1;
    let body: Transfer = Transfer{
          queryId: msg.queryId,         
          newOwner: self.owner,
          responseDestination: self.owner,
          customPayload: null,
          forwardAmount: 0,
          forwardPayload: emptySlice()
    };

    while (i > 0) { 
      if(i == self.nftCounter - 40){
        self.nftCounter = i + 1;

        send(SendParameters{
          to: myAddress(),
          value: 0,
          mode: SendIgnoreErrors + SendRemainingBalance,
          body: AdminWithdrawalAllNFTs{
            queryId: msg.queryId
          }.toCell()
        });
        return;
      }          
      let sentNft: Address = self.nfts.get(i)!!;

      send(SendParameters{
        to: sentNft,
        value: ton("0.05"),
        mode: SendIgnoreErrors,
        body: body.toCell()
      });
      self.nfts.set(i, null);

      i = i - 1;
    }

    let lastNft: Address = self.nfts.get(0)!!;

    send(SendParameters{
        to: lastNft,
        value: 0,
        mode: SendIgnoreErrors + SendRemainingBalance,
        body: body.toCell()
    });

    self.nfts = emptyMap();
  }

  get fun profit(): Int { 
    if(myBalance() < ton("0.1")){
      return 0;
    }
    return myBalance() - ton("0.1");
  }
  
  get fun nfts(): map<Int as uint16, Address> { 
    return self.nfts;
  }
}