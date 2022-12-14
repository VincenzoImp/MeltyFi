import React, { useState } from 'react';
import Button from 'react-bootstrap/Button';
import Form from 'react-bootstrap/Form';
import Modal from 'react-bootstrap/Modal';
import Card from 'react-bootstrap/Card';
import { ethers } from "ethers";
import MeltyFiNFT from "../ABIs/MeltyFiNFT.json";
import { addressMeltyFiNFT, sdk } from "../App";
import { Alert, Row, Col, Container } from 'react-bootstrap';
import { useAddress } from "@thirdweb-dev/react";


async function buyWonkaBars(wonkaBarPrice, lotteryId) {

	try {
		const provider = new ethers.providers.Web3Provider(window.ethereum)
		await provider.send("eth_requestAccounts", []);
		const signer = provider.getSigner();
		let meltyfi = new ethers.Contract(addressMeltyFiNFT, MeltyFiNFT, provider);
		meltyfi = meltyfi.connect(signer);
		await meltyfi.buyWonkaBars(lotteryId, wonkaBarPrice);
	}
	catch (err) {
		return err.name;
	}
	return 0;
}

function BuyWonkaBar(props) {
	const [show, setShow] = useState(false);
	const [showAlert, setShowAlert] = useState(false);
	const [wonkaBarQuantity, setWonkaBarQuantity] = useState(1);

	/** 
	const meltyfi = async () => { await sdk.getContract(addressMeltyFiNFT, MeltyFiNFT) };
	const [, , , , , , , wonkaBarsSold, wonkaBarsMaxSupply,] = async () => {
		await meltyfi.call(
			"getLottery", props.lotteryId)
	};
	const address = useAddress();
	const maxPercentage = async () => { await meltyfi.call("getUpperLimitBalanceOfPercentage") };
	const balance = async () => { await meltyfi.call("balanceOf", address) };
	const maxForMe = wonkaBarsMaxSupply * maxPercentage / 100 - balance;
	const maxAmountToBuy = Math.min(maxForMe, wonkaBarsMaxSupply - wonkaBarsSold);
	*/

	const handleQuantityChange = (event) => {
		const input = parseInt(event.target.value);
		if (isNaN(input) || input <= 0) {
			setWonkaBarQuantity(1);
		} else /**if (input > maxAmountToBuy) {
			setWonkaBarQuantity(maxAmountToBuy);
		} else */ {
			setWonkaBarQuantity(input);
		}
	};

	const handleShow = () => setShow(true);
	const handleClose = () => setShow(false);
	const handleBuy = async () => {
		const result = await buyWonkaBars(props.wonkaBarPrice * wonkaBarQuantity, props.lotteryId);
		if (result === 0) {
			setShow(false);
		}
		else {
			setShowAlert(true);
			console.log(result);
		}
	};

	return (
		<>
			<Button className="CardButton" onClick={handleShow}>
				Buy WonkaBars
			</Button>
			<Modal show={show} onHide={handleClose}>
				<Modal.Header closeButton className='BgColor2 TextColor1'>
					<Modal.Title>Buy WonkaBars for {props.collection} #{props.tokenId}</Modal.Title>
				</Modal.Header>
				<Modal.Body className='BgColor1 TextColor2'>
					<Container align='center' className='pb-3'>
						<Card className='Card'>
							<Card.Img className='CardImg' src={props.nftImg} />
						</Card>
					</Container>
					<Form>
						<Form.Group className="mb-3" controlId="buyWonkaForm.ControlInput1">
							<Row>
								<Col>
									<Form.Label className='pt-2'>WonkaBar amount to buy</Form.Label>
								</Col>
								<Col>
									<Form.Control
										type="number"
										value={wonkaBarQuantity}
										autoFocus
										onChange={handleQuantityChange}
										className='BgColor2 TextColor1'
									/>
								</Col>
							</Row>
						</Form.Group>
					</Form>
					<div className='pt-2'>Total cost: {props.wonkaBarPrice * wonkaBarQuantity} ETH</div>
					<Alert variant="danger" show={showAlert} onClose={() => setShowAlert(false)} dismissible>
						<Alert.Heading>Oh snap! You got an error!</Alert.Heading>
						<p>Please try again.</p>
					</Alert>

				</Modal.Body>
				<Modal.Footer className='BgColor2 TextColor1'>
					<Button variant="secondary" className="TextColor2" onClick={handleClose}>
						Cancel
					</Button>
					<Button className="CardButton" onClick={handleBuy}>
						Buy WonkaBars
					</Button>
				</Modal.Footer>
			</Modal>

		</>
	);
}

export default BuyWonkaBar;