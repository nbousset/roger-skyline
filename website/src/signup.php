<?php
include 'utils.php';

function get_email()
{
	if (!isset($_POST['email']) || empty($_POST['email'])) {
		error('signupform.php', 'All fields must be completed');
	}
	if (strlen($_POST['email']) > 128) {
		error('signupform.php', 'Your email is too long');
	}
	$email = htmlspecialchars($_POST['email']);
	return $email;
}

function get_passw()
{
	if (!isset($_POST['passw']) || empty($_POST['passw'])) {
		error('signupform.php', 'All fields must be completed.');
	}
	$passw = htmlspecialchars($_POST['passw']);
	$passw = password_hash($passw, PASSWORD_DEFAULT);
	if (strlen($_POST['passw']) > 256) {
		error('signupform.php', 'Your password is too long.');
	}
	return $passw;
}

function update_db($email, $passw)
{

	$conndb = new mysqli("127.0.0.1", "membersDBadmin", "passwordDBadmin", "membersDB");
	$request = "SELECT * FROM members WHERE email='$email'"; 
	$result = $conndb->query($request);
	if ($result->num_rows) {
		$conndb->close();
		error('signupform.php', 'This email is already registered.');
	}
	$request = "INSERT INTO members (email,passw) VALUES ('$email','$passw')";
	$conndb->query($request);
	$conndb->close();
}

session_start();
$email = get_email();
$passw = get_passw();
update_db($email, $passw);
$_SESSION['email'] = $email;
header('Location: signin.php');
exit();

?>
