import React, { useEffect,useState } from 'react';
import Button from 'react-bootstrap/Button';
import Form from 'react-bootstrap/Form';
import Modal from 'react-bootstrap/Modal';
import Card from 'react-bootstrap/Card';
import {ethers} from "ethers";
import MeltyFiNFT from "../ABIs/MeltyFiNFT.json";
import {addressMeltyFiNFT} from "../App";
import { Alert } from 'react-bootstrap';

async function callCreateLottery(duration, prizeContract, prizeTokenId, wonkaBarPrice, wonkaBarsMaxSupply){
    const provider = new ethers.providers.Web3Provider(window.ethereum)
    await provider.send("eth_requestAccounts", []);
    const signer = provider.getSigner();

        /*contract.on("approvedNFT", (event) => {
        //actually create the lottery ;
      });*/
    
      let meltyfi = new ethers.Contract(addressMeltyFiNFT, MeltyFiNFT, provider);
      meltyfi = meltyfi.connect(signer);
      try{
        const response = await meltyfi.createLottery(duration, prizeContract, prizeTokenId, wonkaBarPrice, wonkaBarsMaxSupply);
      }
     catch (err) {
      return err;
    }
      return 0;
}

async function callApprove(prizeContract, prizeTokenId) {
    const provider = new ethers.providers.Web3Provider(window.ethereum)
    await provider.send("eth_requestAccounts", []);
    const signer = provider.getSigner();
    
    const contractApprove = new ethers.Contract(prizeContract, [{
        "inputs": [{
            "internalType": "address", "name": "to", "type": "address"
        }, {"internalType": "uint256", "name": "tokenId", "type": "uint256"}],
        "name": "approve",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }], provider);
    const contractWithSigner = contractApprove.connect(signer);

    try{
        const approveResponse = await contractWithSigner.approve(addressMeltyFiNFT, prizeTokenId);
        console.log(approveResponse);
      }
     catch (err) {
      return err;
    }
      return 0;

  }
  

  function CreateLottery(props) {
    const [show, setShow] = useState(false);
    const [showAlert, setShowAlert] = useState(false);
    const [wonkaBarPrice, setWonkaBarPrice] = useState(0);
    const [wonkaBarMaxSupply, setWonkaBarMaxSupply] = useState(0);
    const [duration, setDuration] = useState(0);
  
    const handleDurationChange = (event) => {
      const input = parseInt(event.target.value) * 86400;
      if(isNaN(input) || input <= 0){
        setDuration(0);
      }else {
        setDuration(input);
      }
    };

    const handleWonkaBarMaxSupply = (event) => {
        const input = parseInt(event.target.value);
        if(isNaN(input) || input <= 0){
            setWonkaBarMaxSupply(0);
        }else {
            setWonkaBarMaxSupply(input);
        }
      };
  
      const handleWonkaBarPrice = (event) => {
        const input = ethers.utils.parseEther(event.target.value);
        if(isNaN(input) || input <= 0){
            setWonkaBarPrice(0);
        }else {
            setWonkaBarPrice(input);
        }
      };

    
    const handleShow = () => setShow(true);
    const handleClose = () => setShow(false);
    const handleApprove = async () => {
        const result = await callApprove(props.contract, props.tokenId);
        if (result == 0){
        }
        else{
          setShowAlert(true);
          console.log(result);
        }
      };
    const handleBuy = async () => {
      const result = await callCreateLottery(duration, props.contract, props.tokenId, wonkaBarPrice, wonkaBarMaxSupply);
      if (result == 0){
          setShow(false);
      }
      else{
        setShowAlert(true);
        console.log(result);
      }
    };
  
    return (
        <>
        <Button className="CardButton" onClick={handleShow}>
          Create Lottery
        </Button>
        <Modal show={show} onHide={handleClose}>
          <Modal.Header closeButton>
            <Modal.Title>Create Lottery for {props.tokenId}@{props.collection} </Modal.Title>
          </Modal.Header>
          <Modal.Body>
            <Card className='Card'>
              <Card.Img className='CardImg' src={props.nftImg}/>
          </Card>
          <Form>
              <Form.Group className="mb-3" controlId="createLotteryForm.ControlInput1">
                <Form.Label>Price of a wonka bar (ethers)</Form.Label>
                <Form.Control
                  type="number"
                  placeholder="0.04"
                  autoFocus
                  step="0.001"
                  onChange={handleWonkaBarPrice}
                />
              </Form.Group>
              <Form.Group className="mb-3" controlId="createLotteryForm.ControlInput2">
                <Form.Label>WonkaBar max supply</Form.Label>
                <Form.Control
                  type="number"
                  placeholder="100"
                  autoFocus
                  onChange={handleWonkaBarMaxSupply}
                />
              </Form.Group>
              <Form.Group className="mb-3" controlId="createLotteryForm.ControlInput3">
                <Form.Label>Duration (days)</Form.Label>
                <Form.Control
                  type="number"
                  placeholder="1000"
                  autoFocus
                  onChange={handleDurationChange}
                />
              </Form.Group>
            </Form>
            <p>Total revenue: {(ethers.utils.formatEther((ethers.BigNumber.from(wonkaBarPrice))) ) * parseInt(wonkaBarMaxSupply)}  ethers</p>
            <Alert variant="danger" show={showAlert} onClose={() => setShowAlert(false)} dismissible>
            <Alert.Heading>Oh snap! You got an error!</Alert.Heading>
            <p>Please try again.</p>
            </Alert>
  
          </Modal.Body>
          <Modal.Footer>
            <Button variant="secondary" onClick={handleClose}>
              Cancel
            </Button>
            <Button className="CardButton" onClick={handleApprove}>
              Approve token
            </Button>
            <Button className="CardButton" onClick={handleBuy}>
              Create lottery
            </Button>
          </Modal.Footer>
        </Modal>
        </>
    );
  }

export default CreateLottery;