import {Card, Col, Container, Row} from "react-bootstrap";
import {useAddress} from "@thirdweb-dev/react";
import MeltyFiNFT from "../contracts/MeltyFiNFT.json";
import ChocoChip from "../contracts/ChocoChip.json";
import {useEffect, useState} from "react";
import LotteryCard from "../components/lotteryCard";
import {addressMeltyFiNFT, sdk} from "../App";
import Button from "react-bootstrap/Button";
import {ethers} from "ethers";


async function asyncFilter(arr, predicate) {
    const results = await Promise.all(arr.map(predicate));
    return arr.filter((_v, index) => results[index]);
}

// async function asyncMap(arr, predicate) {
//     return await Promise.all(arr.map(predicate));
// }

async function loadLotteries(meltyfi, address) {
    let [owned, applied] = await Promise.all([
        asyncFilter(
            await meltyfi.call("ownedLotteryIds", address),
            async lottery => await meltyfi.call("getLotteryState", lottery) === 0
        ),
        meltyfi.call("holderInLotteryIds", address)
    ]);
    return [owned, applied];
}

async function loadMetadata(meltyfi, lottery, address) {
    lottery = parseInt(lottery);
    // eslint-disable-next-line no-unused-vars
    let [expirationDate, _, owner, prizeContract, prizeTokenId, state, winner, wonkaBarsSold, wonkaBarsMaxSupply, wonkaBarPrice] = await meltyfi.call(
        "getLottery", lottery);
    let [contract, wonkaBarsOwned] = await Promise.all([
        sdk.getContract(prizeContract, "nft-collection"),
        meltyfi.call("balanceOf", address, lottery),
    ]);
    let [nft, collection, amountToRepay] = await Promise.all([
        contract.get(prizeTokenId),
        contract.call("name"),
        meltyfi.call("amountToRepay", lottery)
    ]);
    expirationDate = new Date(Number(expirationDate) * 1000);
    wonkaBarsMaxSupply = Number(wonkaBarsMaxSupply);
    wonkaBarsSold = Number(wonkaBarsSold);
    wonkaBarsOwned = Number(wonkaBarsOwned);
    return {
        lottery,
        name: nft.metadata.name,
        image: nft.metadata.image,
        prizeTokenId: nft.metadata.id,
        collection,
        owner,
        expirationDate,
        wonkaBarsMaxSupply,
        wonkaBarsSold,
        wonkaBarsOwned,
        wonkaBarPrice,
        winner,
        state,
        amountToRepay
    };
}

async function getChocoChips(meltyfi, address) {
    const chocoChip = await sdk.getContract(await meltyfi.call("addressChocoChip"), ChocoChip);
    return await chocoChip.call("balanceOf", address);
}

async function loadProfileData(address) {
    if (address === undefined)
        return [[], [], [], 0]
    const meltyfi = await sdk.getContract(addressMeltyFiNFT, MeltyFiNFT);
    let [owned, applied] = await loadLotteries(meltyfi, address);
    let fetched = {};
    const ownedMetadata = new Array(0);
    // eslint-disable-next-line no-unused-vars
    for (const [_, lottery] of Object.entries(owned)) {
        if (fetched[lottery] === undefined) {
            const metadata = await loadMetadata(meltyfi, lottery, address)
            fetched[lottery] = metadata;
            ownedMetadata.push(metadata);
        } else {
            ownedMetadata.push(fetched[lottery]);
        }
    }
    const appliedMetadata = new Array(0);
    // eslint-disable-next-line no-unused-vars
    for (const [_, lottery] of Object.entries(applied)) {
        if (fetched[lottery] === undefined) {
            const metadata = await loadMetadata(meltyfi, lottery, address)
            fetched[lottery] = metadata;
            appliedMetadata.push(metadata);
        } else {
            appliedMetadata.push(fetched[lottery]);
        }
    }
    const chocoChips = Number(await getChocoChips(meltyfi, address));
    return [ownedMetadata, appliedMetadata, chocoChips];
}

function getOwnedCards(lotteries) {
    return lotteries.map((data) => {
        let text = <Card.Text>
            <li>Expire date: {data.expirationDate.toLocaleString()}</li>
            <li>
                Wonka Bars
                sold: {data.wonkaBarsSold}/{data.wonkaBarsMaxSupply} ( {data.wonkaBarsSold / data.wonkaBarsMaxSupply * 100}%)
            </li>
        </Card.Text>
        const toRepayETH = ethers.utils.formatUnits(data.amountToRepay, "ether");
        return <Col>
            {LotteryCard({
                src: data.image,
                tokenId: data.prizeTokenId,
                collection: data.collection,
                text,
                lotteryId: data.lottery,
                action: <Button className='CardButton' onClick={
                    async () => {
                        const provider = new ethers.providers.Web3Provider(window.ethereum)
                        await provider.send("eth_requestAccounts", []);
                        const signer = provider.getSigner();
                        let meltyfi = new ethers.Contract(addressMeltyFiNFT, MeltyFiNFT, provider);
                        meltyfi = meltyfi.connect(signer);
                        const response = await meltyfi.repayLoan(
                            data.lottery,
                            {value: ethers.utils.parseEther(toRepayETH.toString())}
                        );
                        console.log("response", response);
                    }
                }>
                    Repay {toRepayETH.toString()}ETH
                </Button>
            })}
        </Col>
    });
}

/*
    let button = undefined;
    if (onClickFunction !== undefined) {
        button = <Button className='CardButton' onClick={onClickFunction}>{onClickText}</Button>;
    }*/

function getAppliedCards(lotteries) {
    return lotteries.map((data) => {
        let text, action = undefined;
        if (data.state === 0) {
            text = <Card.Text>
                <li>Expire date: {data.expirationDate.toLocaleString()}</li>
                <li>Wonka Bars owned: {data.wonkaBarsOwned}</li>
                <li>Wonka Bars sold: {data.wonkaBarsSold}/{data.wonkaBarsMaxSupply}</li>
            </Card.Text>
        } else {
            let state, winner = undefined, receive;
            action = <Button className='CardButton' onClick={async () => {
                const provider = new ethers.providers.Web3Provider(window.ethereum)
                await provider.send("eth_requestAccounts", []);
                const signer = provider.getSigner();
                let meltyfi = new ethers.Contract(addressMeltyFiNFT, MeltyFiNFT, provider);
                meltyfi = meltyfi.connect(signer);
                const response = await meltyfi.meltWonkaBars(data.lottery, data.wonkaBarsOwned);
                console.log("response", response);
            }}>
                Melt {data.wonkaBarsOwned} WonkaBars
            </Button>;
            if (data.state === 1) {
                state = "Canceled";
                winner = "No winner";
                receive = "refund and ChocoChips";
            } else {
                state = "Concluded";
                const url = `https://goerli.etherscan.io/address/${winner}`;
                winner = <a href={url}>Winner</a>;
                receive = "ChocoChips";
            }
            text = <Card.Text>
                <li>State: {state}</li>
                <li>{winner}</li>
                <li>Wonka Bars owned: {data.wonkaBarsOwned}</li>
                <li>Wonka Bars sold: {data.wonkaBarsSold}/{data.wonkaBarsMaxSupply}</li>
                <li>You will receive: {receive}</li>
            </Card.Text>
        }
        return <Col>
            {LotteryCard({
                src: data.image,
                tokenId: data.prizeTokenId,
                collection: data.collection,
                text,
                lotteryId: data.lottery,
                action
            })}
        </Col>;
    });
}

function Profile() {
    const address = useAddress();
    const [profileData, setProfileData] = useState([[], [], [], 0]);
    useEffect(() => {
        loadProfileData(address).then(setProfileData)
    }, [address]);
    // eslint-disable-next-line no-unused-vars
    const [owned, applied, chocoChips] = profileData;
    let lotteriesSection;
    if (address !== undefined) {
        lotteriesSection = <Container>
            <div>Your ChocoChip balance: {chocoChips}</div>
            Owned:<br/>
            <Container>
                <Row>{getOwnedCards(owned)}</Row>
            </Container>
            Applied:<br/>
            <Container>
                <Row>{getAppliedCards(applied)}</Row>
            </Container>
        </Container>
    } else {
        lotteriesSection = <p>Connect your wallet to see your profile</p>
    }
    return <Container>
        <h1>Chi sono</h1>
        The standard Lorem Ipsum passage<br/>
        {lotteriesSection}
    </Container>;
}

export default Profile;
