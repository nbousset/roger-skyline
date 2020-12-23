<?php
include 'utils.php';

function get_email()
{
	if (!isset($_POST['email']) || empty($_POST['email'])) {
		error('signinform.php', 'All fields must be completed');
	}
	$email = htmlspecialchars($_POST['email']);
	return $email;
}

function get_passw()
{
	if (!isset($_POST['passw']) || empty($_POST['passw'])) {
		error('signinform.php', 'All fields must be completed.');
	}
	$password = htmlspecialchars($_POST['passw']);
	#$password = password_hash($password, PASSWORD_DEFAULT);
	return $password;
}

function check_db($email, $passw)
{
	$conndb = new mysqli("127.0.0.1", "membersDBadmin", "passwordDBadmin", "membersDB");
	$request = "SELECT * FROM members WHERE email='$email'"; 
	$result = $conndb->query($request);
	if ($result->num_rows == 0) {
		$conndb->close();
		error('signinform.php', 'You are not registered.');
	}
	$member = $result->fetch_assoc();
	if (!password_verify($passw, $member['passw'])) {
		$conndb->close();
		error('signinform.php', 'Wrong password.');
	}
	$conndb->close();
}

if (!isset($_SESSION['email'])) {
	$email = get_email();
	$passw = get_passw();
	check_db($email, $passw);
	$_SESSION['email'] = $email;
}
header('Location: homepage.php');
exit();

?>
