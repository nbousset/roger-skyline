<?php

function delete_member($email)
{
	$conndb = new mysqli("127.0.0.1", "membersDBadmin", "passwordDBadmin", "membersDB");
	$request = "DELETE FROM members WHERE email='$email'"; 
	$result = $conndb->query($request);
	$conndb->close();
}

session_start();
delete_member($_SESSION['email']);
$_SESSION['email'] = NULL;
header('Location: index.php');
exit();

?>
